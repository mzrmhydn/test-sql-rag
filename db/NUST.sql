-- =============================================================================
-- NUST University Database - MySQL 8.0+ Schema + Seed Data
-- =============================================================================
-- A relational schema for NUST spanning two connected pipelines:
--   * Admissions : applicant -> test_attempt/entry_test -> application -> offer
--   * Academics  : school -> program/course (via program_course) -> section
--                  -> enrollment <- student
--
-- KEY DESIGN DECISIONS
-- 1. VARCHAR primary keys are used throughout. Entity IDs are human-readable:
--    program_id = program code ('BSCS'), course_code itself is the PK of
--    course, school_id = abbreviation ('SEECS'), term_id = compact code
--    ('FA25' for Fall 2025), etc. This makes joins and seed data readable
--    without surrogate lookup tables.
-- 2. Student carries a DIRECT FK to both program (program_id) and applicant
--    (applicant_id) — a deliberate denormalization over reaching these
--    through application. See Phase2_Normalization_Analysis.md §2 for the
--    trade-off (query ergonomics vs BCNF purity). UNIQUE(applicant_id) on
--    student enforces the 1:1 applicant-becomes-student cardinality.
-- 3. Course is owned by a school, not a program. Program<->Course is a real
--    M:N relationship captured in the program_course junction (with is_core
--    and recommended_semester on the junction).
-- 4. Prerequisites are modelled as a self-referential junction (prerequisite)
--    so a course can have many prereqs and be a prereq of many others.
-- 5. The offer entity separates the act of ISSUING an admission offer from
--    the application itself: an offer has its own issue_date / expiry_date
--    and a status lifecycle (Issued -> Accepted / Declined / Expired).
-- 6. Enrollment is keyed by the composite (student_id, section_id); grade is
--    an ENUM that is NULL while the section is still in progress or if a
--    grade has not yet been reported. attendance_percentage is a live metric.
-- =============================================================================

DROP DATABASE IF EXISTS nust_university;
CREATE DATABASE nust_university
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
USE nust_university;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP PROCEDURE IF EXISTS transfer_student_to_section;
DROP PROCEDURE IF EXISTS accept_admission;
DROP FUNCTION  IF EXISTS is_eligible_for_engineering;
DROP TRIGGER   IF EXISTS auto_update_application_status;
DROP TRIGGER   IF EXISTS enforce_class_capacity;
DROP VIEW      IF EXISTS classroom_utilization;
DROP VIEW      IF EXISTS student_transcript;
DROP TABLE IF EXISTS enrollment;
DROP TABLE IF EXISTS section;
DROP TABLE IF EXISTS offer;
DROP TABLE IF EXISTS student;
DROP TABLE IF EXISTS application;
DROP TABLE IF EXISTS test_attempt;
DROP TABLE IF EXISTS entry_test;
DROP TABLE IF EXISTS applicant;
DROP TABLE IF EXISTS prerequisite;
DROP TABLE IF EXISTS program_course;
DROP TABLE IF EXISTS course;
DROP TABLE IF EXISTS classroom;
DROP TABLE IF EXISTS term;
DROP TABLE IF EXISTS program;
DROP TABLE IF EXISTS faculty;
DROP TABLE IF EXISTS school;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- ADMINISTRATIVE STRUCTURE
-- =============================================================================

CREATE TABLE school (
    school_id         VARCHAR(10)  NOT NULL,
    school_name       VARCHAR(150) NOT NULL,
    abbreviation      VARCHAR(20)  NOT NULL,
    established_year  SMALLINT,
    PRIMARY KEY (school_id),
    UNIQUE KEY uq_school_name         (school_name),
    UNIQUE KEY uq_school_abbreviation (abbreviation)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE faculty (
    faculty_id   VARCHAR(10)  NOT NULL,
    school_id    VARCHAR(10)  NOT NULL,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(100) NOT NULL,
    designation  ENUM('Lecturer','Assistant Professor','Associate Professor','Professor') NOT NULL,
    PRIMARY KEY (faculty_id),
    UNIQUE KEY uq_faculty_email (email),
    FOREIGN KEY (school_id) REFERENCES school(school_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE program (
    program_id       VARCHAR(15)  NOT NULL,
    school_id        VARCHAR(10)  NOT NULL,
    program_name     VARCHAR(100) NOT NULL,
    degree_type      ENUM('BS','BE','BBA','BArch','MS','PhD') NOT NULL,
    total_semesters  TINYINT      NOT NULL,
    total_credits    SMALLINT     NOT NULL,
    total_seats      SMALLINT     NOT NULL,
    PRIMARY KEY (program_id),
    UNIQUE KEY uq_program_school_name (school_id, program_name),
    CONSTRAINT chk_program_semesters CHECK (total_semesters BETWEEN 2 AND 14),
    CONSTRAINT chk_program_credits   CHECK (total_credits   > 0),
    CONSTRAINT chk_program_seats     CHECK (total_seats     > 0),
    FOREIGN KEY (school_id) REFERENCES school(school_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- COURSE CATALOGUE AND CURRICULUM
-- =============================================================================

CREATE TABLE course (
    course_code    VARCHAR(15)  NOT NULL,
    school_id      VARCHAR(10)  NOT NULL,
    course_title   VARCHAR(100) NOT NULL,
    course_type    ENUM('Theory','Lab','Theory+Lab','Studio','Seminar') NOT NULL DEFAULT 'Theory',
    credit_hours   TINYINT      NOT NULL,
    contact_hours  TINYINT      NOT NULL,
    PRIMARY KEY (course_code),
    CONSTRAINT chk_course_credit_hours  CHECK (credit_hours  BETWEEN 0 AND 6),
    CONSTRAINT chk_course_contact_hours CHECK (contact_hours BETWEEN 0 AND 10),
    FOREIGN KEY (school_id) REFERENCES school(school_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Self-referential M:N on course (a course has many prereqs, and may itself
-- be a prereq of many other courses).
CREATE TABLE prerequisite (
    course_code         VARCHAR(15) NOT NULL,
    prereq_course_code  VARCHAR(15) NOT NULL,
    PRIMARY KEY (course_code, prereq_course_code),
    CONSTRAINT chk_prereq_not_self CHECK (course_code <> prereq_course_code),
    FOREIGN KEY (course_code)        REFERENCES course(course_code) ON DELETE CASCADE,
    FOREIGN KEY (prereq_course_code) REFERENCES course(course_code) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction (with attrs): program M <-> M course
CREATE TABLE program_course (
    program_id            VARCHAR(15) NOT NULL,
    course_code           VARCHAR(15) NOT NULL,
    recommended_semester  TINYINT     NOT NULL,
    is_core               BOOLEAN     NOT NULL DEFAULT TRUE,
    PRIMARY KEY (program_id, course_code),
    CONSTRAINT chk_pc_semester CHECK (recommended_semester BETWEEN 1 AND 14),
    FOREIGN KEY (program_id)  REFERENCES program(program_id)  ON DELETE CASCADE,
    FOREIGN KEY (course_code) REFERENCES course(course_code) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE term (
    term_id        VARCHAR(15) NOT NULL,
    term_name      ENUM('Fall','Spring','Summer') NOT NULL,
    academic_year  SMALLINT    NOT NULL,
    start_date     DATE        NOT NULL,
    end_date       DATE        NOT NULL,
    PRIMARY KEY (term_id),
    UNIQUE KEY uq_term_name_year (term_name, academic_year),
    CONSTRAINT chk_term_dates CHECK (end_date > start_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE classroom (
    classroom_id  VARCHAR(15) NOT NULL,
    building      VARCHAR(50) NOT NULL,
    room_number   VARCHAR(20) NOT NULL,
    capacity      SMALLINT    NOT NULL,
    PRIMARY KEY (classroom_id),
    UNIQUE KEY uq_classroom_building_room (building, room_number),
    CONSTRAINT chk_classroom_capacity CHECK (capacity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- ADMISSIONS PIPELINE
-- =============================================================================

CREATE TABLE applicant (
    applicant_id       VARCHAR(15)  NOT NULL,
    full_name          VARCHAR(100) NOT NULL,
    cnic               VARCHAR(20)  NOT NULL,
    email              VARCHAR(100) NOT NULL,
    high_school_board  ENUM('FBISE','AKU-EB','Cambridge','Other') NOT NULL,
    high_school_score  DECIMAL(6,2) NOT NULL,
    best_test_score    DECIMAL(5,2),
    PRIMARY KEY (applicant_id),
    UNIQUE KEY uq_applicant_cnic  (cnic),
    UNIQUE KEY uq_applicant_email (email),
    CONSTRAINT chk_applicant_hs_score   CHECK (high_school_score BETWEEN 0 AND 1100),
    CONSTRAINT chk_applicant_test_score CHECK (best_test_score IS NULL OR best_test_score BETWEEN 0 AND 200)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE entry_test (
    test_id       VARCHAR(15) NOT NULL,
    academic_year SMALLINT    NOT NULL,
    net_number    TINYINT     NOT NULL,
    test_type     ENUM('Engineering','CS','Business','Architecture','Biosciences','Chemical') NOT NULL,
    test_date     DATE        NOT NULL,
    total_marks   SMALLINT    NOT NULL DEFAULT 200,
    PRIMARY KEY (test_id),
    UNIQUE KEY uq_net_session (academic_year, net_number, test_type),
    CONSTRAINT chk_net_number       CHECK (net_number BETWEEN 1 AND 4),
    CONSTRAINT chk_test_total_marks CHECK (total_marks > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction: applicant M <-> M entry_test (an applicant takes each test at most once)
CREATE TABLE test_attempt (
    applicant_id  VARCHAR(15)  NOT NULL,
    test_id       VARCHAR(15)  NOT NULL,
    score         DECIMAL(5,2) NOT NULL,
    PRIMARY KEY (applicant_id, test_id),
    CONSTRAINT chk_attempt_score CHECK (score >= 0),
    FOREIGN KEY (applicant_id) REFERENCES applicant(applicant_id) ON DELETE CASCADE,
    FOREIGN KEY (test_id)      REFERENCES entry_test(test_id)     ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction (with attrs): applicant M <-> M program, scoped by term.
CREATE TABLE application (
    application_id      VARCHAR(15)  NOT NULL,
    applicant_id        VARCHAR(15)  NOT NULL,
    program_id          VARCHAR(15)  NOT NULL,
    term_id             VARCHAR(15)  NOT NULL,
    snapshot_hs_score   DECIMAL(6,2) NOT NULL,
    snapshot_best_test  DECIMAL(5,2),
    aggregate_score     DECIMAL(5,2),
    submission_date     DATE         NOT NULL,
    status              ENUM('Pending','Selected','Waitlisted','Rejected','Enrolled','Declined') NOT NULL DEFAULT 'Pending',
    PRIMARY KEY (application_id),
    UNIQUE KEY uq_application_applicant_program_term (applicant_id, program_id, term_id),
    FOREIGN KEY (applicant_id) REFERENCES applicant(applicant_id) ON DELETE CASCADE,
    FOREIGN KEY (program_id)   REFERENCES program(program_id)     ON DELETE CASCADE,
    FOREIGN KEY (term_id)      REFERENCES term(term_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- application 1 <-> 0..1 offer (at most one offer per application)
CREATE TABLE offer (
    offer_id        VARCHAR(15) NOT NULL,
    application_id  VARCHAR(15) NOT NULL,
    issue_date      DATE        NOT NULL,
    expiry_date     DATE        NOT NULL,
    status          ENUM('Issued','Accepted','Declined','Expired') NOT NULL DEFAULT 'Issued',
    PRIMARY KEY (offer_id),
    UNIQUE KEY uq_offer_application (application_id),
    CONSTRAINT chk_offer_dates CHECK (expiry_date > issue_date),
    FOREIGN KEY (application_id) REFERENCES application(application_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- applicant 1 <-> 0..1 student; every student is also linked to their program.
CREATE TABLE student (
    student_id        VARCHAR(15)  NOT NULL,
    program_id        VARCHAR(15)  NOT NULL,
    applicant_id      VARCHAR(15)  NOT NULL,
    full_name         VARCHAR(100) NOT NULL,
    email             VARCHAR(100) NOT NULL,
    current_semester  TINYINT      NOT NULL DEFAULT 1,
    enrollment_date   DATE         NOT NULL,
    gpa               DECIMAL(3,2),
    PRIMARY KEY (student_id),
    UNIQUE KEY uq_student_applicant (applicant_id),
    UNIQUE KEY uq_student_email     (email),
    CONSTRAINT chk_student_semester CHECK (current_semester BETWEEN 1 AND 14),
    CONSTRAINT chk_student_gpa      CHECK (gpa IS NULL OR gpa BETWEEN 0.00 AND 4.00),
    FOREIGN KEY (program_id)   REFERENCES program(program_id),
    FOREIGN KEY (applicant_id) REFERENCES applicant(applicant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A scheduled offering of a course, in a term, taught by a faculty member, in
-- a classroom. All four links are mandatory.
CREATE TABLE section (
    section_id     VARCHAR(20) NOT NULL,
    course_code    VARCHAR(15) NOT NULL,
    term_id        VARCHAR(15) NOT NULL,
    classroom_id   VARCHAR(15) NOT NULL,
    faculty_id     VARCHAR(10) NOT NULL,
    section_label  VARCHAR(5)  NOT NULL,
    PRIMARY KEY (section_id),
    UNIQUE KEY uq_section_course_term_label (course_code, term_id, section_label),
    FOREIGN KEY (course_code)  REFERENCES course(course_code),
    FOREIGN KEY (term_id)      REFERENCES term(term_id),
    FOREIGN KEY (classroom_id) REFERENCES classroom(classroom_id),
    FOREIGN KEY (faculty_id)   REFERENCES faculty(faculty_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction: student M <-> M section. Grade is NULL while in progress.
CREATE TABLE enrollment (
    student_id             VARCHAR(15)  NOT NULL,
    section_id             VARCHAR(20)  NOT NULL,
    attendance_percentage  DECIMAL(5,2),
    grade                  ENUM('A','A-','B+','B','B-','C+','C','C-','D+','D','F'),
    PRIMARY KEY (student_id, section_id),
    CONSTRAINT chk_enrollment_attendance CHECK (attendance_percentage IS NULL OR attendance_percentage BETWEEN 0 AND 100),
    FOREIGN KEY (student_id) REFERENCES student(student_id),
    FOREIGN KEY (section_id) REFERENCES section(section_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

DELIMITER //

-- Reject enrollments that would exceed the hosting classroom's capacity.
CREATE TRIGGER enforce_class_capacity
BEFORE INSERT ON enrollment
FOR EACH ROW
BEGIN
    DECLARE v_current_count INT;
    DECLARE v_capacity      INT;

    SELECT COUNT(*) INTO v_current_count
      FROM enrollment
     WHERE section_id = NEW.section_id;

    SELECT c.capacity INTO v_capacity
      FROM classroom c
      JOIN section   s ON s.classroom_id = c.classroom_id
     WHERE s.section_id = NEW.section_id;

    IF v_current_count >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Enrollment failed: classroom capacity reached.';
    END IF;
END //

-- When a student is inserted, promote their matching Selected application to
-- 'Enrolled' and flip the associated offer from 'Issued' to 'Accepted'. The
-- student is linked to the application through (applicant_id, program_id).
CREATE TRIGGER auto_update_application_status
AFTER INSERT ON student
FOR EACH ROW
BEGIN
    UPDATE application
       SET status = 'Enrolled'
     WHERE applicant_id = NEW.applicant_id
       AND program_id   = NEW.program_id
       AND status       = 'Selected';

    UPDATE offer o
      JOIN application a ON a.application_id = o.application_id
       SET o.status = 'Accepted'
     WHERE a.applicant_id = NEW.applicant_id
       AND a.program_id   = NEW.program_id
       AND o.status       = 'Issued';
END //

DELIMITER ;

-- =============================================================================
-- INDEXES
-- =============================================================================
-- Goal: cover every FK column that is not already the leftmost column of a PK
-- or UNIQUE key. Each index carries a short note on the query pattern it
-- accelerates. Seek-lookups on FK equality (JOIN and WHERE) are the dominant
-- access pattern across this schema, so single-column BTree indexes are the
-- right default; composite indexes are only used where a UNIQUE constraint
-- already demands them.

-- Accelerates "all faculty in a school" lookups used by HR dashboards and
-- section-scheduling UIs that list candidate teachers for a course.
CREATE INDEX idx_faculty_school         ON faculty(school_id);

-- Accelerates "all programs offered by a school" reports that populate the
-- program picker on admissions and prospectus pages.
CREATE INDEX idx_program_school         ON program(school_id);

-- Accelerates "all courses owned by a school" joins used to build the school's
-- course catalogue view. Without this index every catalogue page would scan.
CREATE INDEX idx_course_school          ON course(school_id);

-- The PK leads with program_id, so lookups by course_code alone would scan the
-- table. This reverse index is used when answering "which programs require
-- course X?" — e.g., before deleting a course.
CREATE INDEX idx_program_course_course  ON program_course(course_code);

-- PK leads with course_code; this reverse index answers "what courses list X as
-- a prerequisite?" which is used by degree-audit reports and course
-- deprecation workflows.
CREATE INDEX idx_prerequisite_prereq    ON prerequisite(prereq_course_code);

-- Admissions queues filter heavily on status ('Pending','Selected',...). This
-- index turns status-only scans into range seeks and is the #1 predicate used
-- by the admissions dashboard.
CREATE INDEX idx_application_status     ON application(status);

-- UNIQUE(applicant_id, program_id, term_id) already covers applicant_id-led
-- probes; this index accelerates "all applications for program X" seat-fill
-- reports, where program_id alone is the predicate.
CREATE INDEX idx_application_program    ON application(program_id);

-- Accelerates "all applications for intake term X" queries used at the start
-- of every admissions cycle to bulk-score that cohort.
CREATE INDEX idx_application_term       ON application(term_id);

-- PK leads with applicant_id; this reverse index answers "everyone who sat for
-- test X" — used for score-distribution reports and publishing results.
CREATE INDEX idx_test_attempt_test      ON test_attempt(test_id);

-- Offer-status dashboards ("how many offers are still Issued vs Accepted?")
-- filter on status. This index avoids a full scan of the offer table.
CREATE INDEX idx_offer_status           ON offer(status);

-- Accelerates "all students in program X" rosters used for academic audits and
-- the auto_update_application_status trigger's matching logic.
CREATE INDEX idx_student_program        ON student(program_id);

-- UNIQUE(course_code, term_id, section_label) already covers course_code-led
-- probes as its leftmost prefix, so this additional index is technically
-- redundant for course_code-only lookups but is kept for explicit documentation
-- of the FK access path (and to avoid optimizer surprises when the unique
-- index is dropped or altered).
CREATE INDEX idx_section_course         ON section(course_code);

-- Accelerates "all sections running in term X" queries used to build the
-- term's timetable and to drive classroom-utilization reports.
CREATE INDEX idx_section_term           ON section(term_id);

-- Accelerates "which sections use classroom X?" queries used by facilities
-- management when a room goes offline for maintenance.
CREATE INDEX idx_section_classroom      ON section(classroom_id);

-- Accelerates "teaching load of faculty X" queries — used for workload
-- reports and for detecting double-booked instructors.
CREATE INDEX idx_section_faculty        ON section(faculty_id);

-- PK leads with student_id; this reverse index answers "who is enrolled in
-- section X?" — the dominant query for class rosters, grade submission, and
-- the enforce_class_capacity trigger's COUNT(*).
CREATE INDEX idx_enrollment_section     ON enrollment(section_id);

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- 1. school ------------------------------------------------------------------
INSERT INTO school (school_id, school_name, abbreviation, established_year) VALUES
('SEECS','School of Electrical Engineering and Computer Science','SEECS',2008),
('SMME' ,'School of Mechanical and Manufacturing Engineering'   ,'SMME' ,2008),
('NBS'  ,'NUST Business School'                                 ,'NBS'  ,2005),
('SADA' ,'School of Art, Design and Architecture'               ,'SADA' ,2010),
('NICE' ,'NUST Institute of Civil Engineering'                  ,'NICE' ,2006),
('S3H'  ,'School of Social Sciences and Humanities'             ,'S3H'  ,2010),
('ASAB' ,'Atta-ur-Rahman School of Applied Biosciences'         ,'ASAB' ,2005),
('SCME' ,'School of Chemical and Materials Engineering'         ,'SCME' ,2009),
('CAMP' ,'Centre for Advanced Mathematics and Physics'          ,'CAMP' ,2007),
('MCS'  ,'Military College of Signals'                          ,'MCS'  ,2002);

-- 2. faculty ----------------------------------------------------------------
INSERT INTO faculty (faculty_id, school_id, full_name, email, designation) VALUES
('F001','SEECS','Arshad Ali'   ,'arshad.ali@seecs.nust.edu.pk'   ,'Professor'),
('F002','SEECS','Shamim Baig'  ,'shamim.baig@seecs.nust.edu.pk'  ,'Assistant Professor'),
('F003','SEECS','Faisal Shafiq','faisal.shafiq@seecs.nust.edu.pk','Associate Professor'),
('F004','SEECS','Noman Qadir'  ,'noman.qadir@seecs.nust.edu.pk'  ,'Lecturer'),
('F005','SMME' ,'Rizwan Riaz'  ,'rizwan.riaz@smme.nust.edu.pk'   ,'Professor'),
('F006','SMME' ,'Ahmad Butt'   ,'ahmad.butt@smme.nust.edu.pk'    ,'Associate Professor'),
('F007','NBS'  ,'Sarah Khan'   ,'sarah.khan@nbs.nust.edu.pk'     ,'Assistant Professor'),
('F008','NBS'  ,'Asim Zafar'   ,'asim.zafar@nbs.nust.edu.pk'     ,'Lecturer'),
('F009','SADA' ,'Hasan Javed'  ,'hasan.javed@sada.nust.edu.pk'   ,'Assistant Professor'),
('F010','NICE' ,'Tahir Mehmood','tahir.mehmood@nice.nust.edu.pk' ,'Professor'),
('F011','ASAB' ,'Ayesha Tariq' ,'ayesha.tariq@asab.nust.edu.pk'  ,'Associate Professor'),
('F012','SCME' ,'Usman Ghadeer','usman.ghadeer@scme.nust.edu.pk' ,'Professor');

-- 3. program (Bachelor students only - no Masters/PhD) -------------------
INSERT INTO program (program_id, school_id, program_name, degree_type, total_semesters, total_credits, total_seats) VALUES
('BSCS'  ,'SEECS','Computer Science'       ,'BS'    , 8,134,150),
('BESE'  ,'SEECS','Software Engineering'   ,'BE'    , 8,136,120),
('BEE'   ,'SEECS','Electrical Engineering' ,'BE'    , 8,136,120),
('BME'   ,'SMME' ,'Mechanical Engineering' ,'BE'    , 8,136,100),
('BIME'  ,'SMME' ,'Industrial Engineering' ,'BE'    , 8,136, 60),
('BBA'   ,'NBS'  ,'Business Administration','BBA'   , 8,132,120),
('BSAF'  ,'NBS'  ,'Accounting and Finance' ,'BBA'   , 8,132, 80),
('BECE'  ,'NICE' ,'Civil Engineering'      ,'BE'    , 8,136,100),
('BArch' ,'SADA' ,'Architecture'           ,'BArch' ,10,160, 50),
('BSAB'  ,'ASAB' ,'Applied Biosciences'    ,'BS'    , 8,134, 60),
('BChemE','SCME' ,'Chemical Engineering'   ,'BE'    , 8,136, 80);

-- 4. course -----------------------------------------------------------------
INSERT INTO course (course_code, school_id, course_title, course_type, credit_hours, contact_hours) VALUES
('CS118' ,'SEECS','Programming Fundamentals'   ,'Theory+Lab',4,5),
('CS212' ,'SEECS','Object Oriented Programming','Theory+Lab',4,5),
('CS220' ,'SEECS','Database Systems'           ,'Theory+Lab',4,5),
('CS330' ,'SEECS','Operating Systems'          ,'Theory+Lab',3,4),
('CS440' ,'SEECS','Machine Learning'           ,'Theory+Lab',3,4),
('SE210' ,'SEECS','Software Requirements Eng'  ,'Theory'    ,3,3),
('SE310' ,'SEECS','Software Design'            ,'Theory'    ,3,3),
('ME101' ,'SMME' ,'Engineering Mechanics'      ,'Theory'    ,3,3),
('ME201' ,'SMME' ,'Thermodynamics'             ,'Theory'    ,3,3),
('MGT101','NBS'  ,'Principles of Management'   ,'Theory'    ,3,3),
('FIN201','NBS'  ,'Financial Accounting'       ,'Theory'    ,3,3),
('CE201' ,'NICE' ,'Circuit Analysis'           ,'Theory+Lab',3,4),
('AR101' ,'SADA' ,'Architecture Studio I'      ,'Studio'    ,4,8),
('BS201' ,'ASAB' ,'Microbiology'               ,'Theory+Lab',3,4),
('CHE201','SCME' ,'Mass Transfer'              ,'Theory'    ,3,3);

-- 5. prerequisite ----------------------------------------------------------
INSERT INTO prerequisite (course_code, prereq_course_code) VALUES
('CS212' ,'CS118'),   -- OOP after Programming Fundamentals
('CS220' ,'CS212'),   -- Databases after OOP
('CS330' ,'CS212'),   -- Operating Systems after OOP
('CS440' ,'CS220'),   -- Machine Learning after Databases
('CS440' ,'CS330'),   -- Machine Learning also requires OS (systems background)
('SE310' ,'SE210'),   -- Software Design after Requirements
('SE310' ,'CS212'),   -- Software Design also requires OOP
('SE310' ,'CS220'),   -- Software Design also requires Databases
('ME201' ,'ME101'),   -- Thermodynamics after Engineering Mechanics
('FIN201','MGT101');  -- Financial Accounting after Principles of Management

-- 6. program_course  (M:N mapping: a course can appear in many programs) ---
INSERT INTO program_course (program_id, course_code, recommended_semester, is_core) VALUES
-- CS118 Programming Fundamentals (shared across BSCS/BESE/BEE)
('BSCS','CS118',1,TRUE),
('BESE','CS118',1,TRUE),
('BEE' ,'CS118',1,TRUE),
-- CS212 OOP
('BSCS','CS212',2,TRUE),
('BESE','CS212',2,TRUE),
-- CS220 Databases
('BSCS','CS220',4,TRUE),
('BESE','CS220',3,TRUE),
-- CS330 Operating Systems
('BSCS','CS330',5,TRUE),
('BESE','CS330',6,FALSE),
-- CS440 Machine Learning
('BSCS','CS440',7,FALSE),
-- SE210 Software Requirements
('BESE','SE210',3,TRUE),
('BSCS','SE210',6,FALSE),
-- SE310 Software Design
('BESE','SE310',5,TRUE),
-- ME101 Engineering Mechanics
('BME' ,'ME101',1,TRUE),
('BIME','ME101',1,TRUE),
-- ME201 Thermodynamics
('BME' ,'ME201',3,TRUE),
-- MGT101 Principles of Management
('BBA' ,'MGT101',1,TRUE),
('BSAF','MGT101',1,TRUE),
-- FIN201 Financial Accounting
('BSAF','FIN201',2,TRUE),
('BBA' ,'FIN201',3,TRUE),
-- CE201 Circuit Analysis
('BECE','CE201' ,2,TRUE),
('BEE' ,'CE201' ,2,TRUE),
-- AR101 Architecture Studio I
('BArch','AR101',1,TRUE),
-- BS201 Microbiology
('BSAB','BS201' ,2,TRUE),
-- CHE201 Mass Transfer
('BChemE','CHE201',3,TRUE);

-- 7. term -------------------------------------------------------------------
INSERT INTO term (term_id, term_name, academic_year, start_date, end_date) VALUES
('FA24','Fall'  ,2024,'2024-09-01','2025-01-15'),
('SP25','Spring',2025,'2025-02-01','2025-06-15'),
('SU25','Summer',2025,'2025-07-01','2025-08-15'),
('FA25','Fall'  ,2025,'2025-09-01','2026-01-15'),
('SP26','Spring',2026,'2026-02-01','2026-06-15'),
('SU26','Summer',2026,'2026-07-01','2026-08-15'),
('FA26','Fall'  ,2026,'2026-09-01','2027-01-15'),
('SP27','Spring',2027,'2027-02-01','2027-06-15'),
('FA27','Fall'  ,2027,'2027-09-01','2028-01-15'),
('SP28','Spring',2028,'2028-02-01','2028-06-15');

-- 8. classroom -------------------------------------------------------------
INSERT INTO classroom (classroom_id, building, room_number, capacity) VALUES
('R01','SEECS Block','CR-01'   , 50),
('R02','SEECS Block','CR-02'   , 50),
('R03','SEECS Block','Lab-A'   , 40),
('R04','SEECS Block','Lab-B'   , 40),
('R05','SMME Block' ,'CR-101'  , 60),
('R06','SMME Block' ,'CR-102'  , 60),
('R07','NBS Block'  ,'Hall-A'  ,100),
('R08','NBS Block'  ,'CR-05'   , 40),
('R09','SADA Block' ,'Studio-1', 30),
('R10','NICE Block' ,'CR-Civil', 50),
('R11','ASAB Block' ,'Lab-Bio' , 35),
('R12','SCME Block' ,'Lab-Chem', 35);

-- 9. applicant -------------------------------------------------------------
INSERT INTO applicant (applicant_id, full_name, cnic, email, high_school_board, high_school_score, best_test_score) VALUES
('A0001','Ali Khan'     ,'35202-1111111-1','ali.khan@test.com'     ,'FBISE'    , 980.00,155.00),
('A0002','Aisha Ahmed'  ,'35202-1111112-2','aisha.ahmed@test.com'  ,'FBISE'    ,1010.00,168.00),
('A0003','Bilal Tariq'  ,'42101-2222223-3','bilal.tariq@test.com'  ,'AKU-EB'   , 880.00,140.00),
('A0004','Fatima Zahra' ,'35202-3333334-4','fatima.zahra@test.com' ,'FBISE'    , 950.00,155.00),
('A0005','Saad Hussain' ,'17301-4444445-5','saad.hussain@test.com' ,'FBISE'    , 905.00,140.00),
('A0006','Omar Sheikh'  ,'36301-5555556-6','omar.sheikh@test.com'  ,'AKU-EB'   , 850.00,125.00),
('A0007','Zainab Rizvi' ,'35202-6666667-7','zainab.rizvi@test.com' ,'Cambridge',1020.00,175.00),
('A0008','Hamza Farooq' ,'33100-7777778-8','hamza.farooq@test.com' ,'FBISE'    , 800.00,110.00),
('A0009','Sana Iqbal'   ,'37405-8888889-9','sana.iqbal@test.com'   ,'FBISE'    , 940.00,152.00),
('A0010','Usman Ali'    ,'54400-9999991-0','usman.ali@test.com'    ,'FBISE'    , 860.00,145.00),
('A0011','Hina Malik'   ,'35202-1112223-1','hina.malik@test.com'   ,'Cambridge', 970.00,160.00),
('A0012','Tariq Mahmood','42101-2223334-2','tariq.mahmood@test.com','AKU-EB'   , 830.00,130.00),
('A0013','Noor Fatima'  ,'35202-3334445-3','noor.fatima@test.com'  ,'FBISE'    , 960.00,155.00),
('A0014','Ahmed Raza'   ,'41303-4445556-4','ahmed.raza@test.com'   ,'FBISE'    , 790.00,115.00),
('A0015','Sara Khan'    ,'35202-5556667-5','sara.khan@test.com'    ,'AKU-EB'   , 890.00,130.00);

-- 10. entry_test (4 NET sessions per academic year, each leading to fall intake) ----
INSERT INTO entry_test (test_id, academic_year, net_number, test_type, test_date, total_marks) VALUES
-- 2025 intake: NET-1 (January)
('T01', 2025, 1, 'Engineering',  '2025-01-15', 200),
('T02', 2025, 1, 'Business',     '2025-01-20', 200),
('T03', 2025, 1, 'Architecture', '2025-01-25', 200),
('T04', 2025, 1, 'Biosciences',  '2025-02-01', 200),
-- 2025 intake: NET-2 (March)
('T05', 2025, 2, 'Engineering',  '2025-03-15', 200),
('T06', 2025, 2, 'Business',     '2025-03-20', 200),
-- 2025 intake: NET-3 (May)
('T07', 2025, 3, 'Engineering',  '2025-05-15', 200),
('T08', 2025, 3, 'CS',           '2025-05-20', 200),
-- 2025 intake: NET-4 (July)
('T09', 2025, 4, 'Engineering',  '2025-07-15', 200),
('T10', 2025, 4, 'Business',     '2025-07-20', 200),
('T11', 2025, 4, 'Chemical',     '2025-07-25', 200),
-- 2026 intake: NET-1 (January)
('T12', 2026, 1, 'Engineering',  '2026-01-15', 200),
('T13', 2026, 1, 'Business',     '2026-01-20', 200),
('T14', 2026, 1, 'Architecture', '2026-01-25', 200),
('T15', 2026, 1, 'Biosciences',  '2026-02-01', 200),
-- 2026 intake: NET-2 (March)
('T16', 2026, 2, 'Engineering',  '2026-03-15', 200),
('T17', 2026, 2, 'Business',     '2026-03-20', 200),
-- 2026 intake: NET-3 (May)
('T18', 2026, 3, 'Engineering',  '2026-05-15', 200),
('T19', 2026, 3, 'CS',           '2026-05-20', 200),
-- 2026 intake: NET-4 (July)
('T20', 2026, 4, 'Engineering',  '2026-07-15', 200);

-- 11. test_attempt (every applicant's best_test_score equals MAX attempt) ---
INSERT INTO test_attempt (applicant_id, test_id, score) VALUES
-- 2025 intake (FA25)
('A0001', 'T01', 155.00),  -- Engineering NET-1 2025
('A0002', 'T01', 168.00),  -- Engineering NET-1 2025
('A0003', 'T01', 140.00),  -- Engineering NET-1 2025
('A0004', 'T02', 155.00),  -- Business NET-1 2025
('A0005', 'T01', 140.00),  -- Engineering NET-1 2025
-- 2026 intake (FA26)
('A0006', 'T13', 125.00),  -- Business NET-1 2026
('A0007', 'T12', 175.00),  -- Engineering NET-1 2026
('A0008', 'T12', 110.00),  -- Engineering NET-1 2026
('A0009', 'T12', 152.00),  -- Engineering NET-1 2026
('A0010', 'T12', 145.00),  -- Engineering NET-1 2026
('A0011', 'T14', 160.00),  -- Architecture NET-1 2026
('A0012', 'T12', 130.00),  -- Engineering NET-1 2026
('A0013', 'T15', 155.00),  -- Biosciences NET-1 2026
('A0014', 'T12', 115.00),  -- Engineering NET-1 2026
('A0015', 'T13', 130.00);  -- Business NET-1 2026

-- 12. application (20 rows) ------------------------------------------------
-- Rows with status='Selected' will be auto-promoted to 'Enrolled' by the
-- auto_update_application_status trigger once a matching student is inserted.
INSERT INTO application (application_id, applicant_id, program_id, term_id, snapshot_hs_score, snapshot_best_test, aggregate_score, submission_date, status) VALUES
('AP001','A0001','BSCS'  ,'FA25', 980.00,155.00,75.50,'2025-07-01','Selected'),
('AP002','A0002','BESE'  ,'FA25',1010.00,168.00,83.10,'2025-07-01','Selected'),
('AP003','A0002','BSCS'  ,'FA25',1010.00,168.00,83.10,'2025-07-01','Waitlisted'),
('AP004','A0003','BME'   ,'FA25', 880.00,140.00,70.20,'2025-07-01','Selected'),
('AP005','A0004','BBA'   ,'FA25', 950.00,155.00,74.80,'2025-07-02','Selected'),
('AP006','A0005','BSCS'  ,'FA25', 905.00,140.00,68.90,'2025-07-05','Selected'),
('AP007','A0005','BEE'   ,'FA25', 905.00,140.00,68.90,'2025-07-05','Waitlisted'),
('AP008','A0006','BSAF'  ,'FA26', 850.00,125.00,65.40,'2026-07-01','Selected'),
('AP009','A0007','BESE'  ,'FA26',1020.00,175.00,85.60,'2026-07-01','Selected'),
('AP010','A0007','BSCS'  ,'FA26',1020.00,175.00,85.60,'2026-07-01','Rejected'),
('AP011','A0008','BChemE','FA26', 800.00,110.00,58.20,'2026-07-02','Rejected'),
('AP012','A0009','BSCS'  ,'FA26', 940.00,152.00,73.40,'2026-07-05','Selected'),
('AP013','A0009','BESE'  ,'FA26', 940.00,152.00,73.40,'2026-07-05','Rejected'),
('AP014','A0010','BECE'  ,'FA26', 860.00,145.00,69.80,'2026-07-07','Selected'),
('AP015','A0011','BArch' ,'FA26', 970.00,160.00,77.90,'2026-07-08','Selected'),
('AP016','A0011','BSAB'  ,'FA26', 970.00,160.00,77.90,'2026-07-08','Rejected'),
('AP017','A0012','BSCS'  ,'FA26', 830.00,130.00,64.10,'2026-07-10','Waitlisted'),
('AP018','A0013','BSAB'  ,'FA26', 960.00,155.00,75.20,'2026-07-12','Selected'),
('AP019','A0014','BME'   ,'FA26', 790.00,115.00,57.60,'2026-07-15','Rejected'),
('AP020','A0015','BBA'   ,'FA26', 890.00,130.00,66.80,'2026-07-18','Selected');

-- 13. offer (12 rows — one per Selected application) ---------------------
-- All offers are seeded with status='Issued'. The student inserts below cause
-- auto_update_application_status to flip the matching offer to 'Accepted'.
-- Offers OF006 (Omar/BSAF) and OF012 (Sara/BBA) stay 'Issued' because no
-- student row is inserted for them in this seed.
INSERT INTO offer (offer_id, application_id, issue_date, expiry_date, status) VALUES
('OF001','AP001','2025-07-20','2025-08-20','Issued'),
('OF002','AP002','2025-07-20','2025-08-20','Issued'),
('OF003','AP004','2025-07-20','2025-08-20','Issued'),
('OF004','AP005','2025-07-20','2025-08-20','Issued'),
('OF005','AP006','2025-07-20','2025-08-20','Issued'),
('OF006','AP008','2026-07-20','2026-08-20','Issued'),
('OF007','AP009','2026-07-20','2026-08-20','Issued'),
('OF008','AP012','2026-07-20','2026-08-20','Issued'),
('OF009','AP014','2026-07-20','2026-08-20','Issued'),
('OF010','AP015','2026-07-20','2026-08-20','Issued'),
('OF011','AP018','2026-07-20','2026-08-20','Issued'),
('OF012','AP020','2026-07-20','2026-08-20','Issued');

-- 14. student (10 rows) --------------------------------------------------
-- Inserting a student fires auto_update_application_status, promoting the
-- matching application from 'Selected' to 'Enrolled' and the offer from
-- 'Issued' to 'Accepted'. Cohort 1 (FA25) students are now in current_semester=2;
-- Cohort 2 (FA26) students are starting current_semester=1.
-- gpa is computed from completed enrollment grades; NULL for students who
-- have no finalized grades yet (Cohort 2, still in their first semester).
INSERT INTO student (student_id, program_id, applicant_id, full_name, email, current_semester, enrollment_date, gpa) VALUES
('S001','BSCS' ,'A0001','Ali Khan'    ,'ali.khan@student.nust.edu.pk'    ,2,'2025-09-01',3.67),
('S002','BESE' ,'A0002','Aisha Ahmed' ,'aisha.ahmed@student.nust.edu.pk' ,2,'2025-09-01',3.74),
('S003','BME'  ,'A0003','Bilal Tariq' ,'bilal.tariq@student.nust.edu.pk' ,2,'2025-09-01',3.50),
('S004','BBA'  ,'A0004','Fatima Zahra','fatima.zahra@student.nust.edu.pk',2,'2025-09-01',4.00),
('S005','BSCS' ,'A0005','Saad Hussain','saad.hussain@student.nust.edu.pk',2,'2025-09-01',3.15),
('S006','BESE' ,'A0007','Zainab Rizvi','zainab.rizvi@student.nust.edu.pk',1,'2026-09-01',NULL),
('S007','BSCS' ,'A0009','Sana Iqbal'  ,'sana.iqbal@student.nust.edu.pk'  ,1,'2026-09-01',NULL),
('S008','BECE' ,'A0010','Usman Ali'   ,'usman.ali@student.nust.edu.pk'   ,1,'2026-09-01',NULL),
('S009','BArch','A0011','Hina Malik'  ,'hina.malik@student.nust.edu.pk'  ,1,'2026-09-01',NULL),
('S010','BSAB' ,'A0013','Noor Fatima' ,'noor.fatima@student.nust.edu.pk' ,1,'2026-09-01',NULL);

-- 15. section ------------------------------------------------------------
INSERT INTO section (section_id, course_code, term_id, classroom_id, faculty_id, section_label) VALUES
-- Fall 2025 (FA25): Cohort 1 intro
('SEC001','CS118' ,'FA25','R03','F001','A'),
('SEC002','CS118' ,'FA25','R04','F004','B'),
('SEC003','SE210' ,'FA25','R01','F003','A'),
('SEC004','ME101' ,'FA25','R05','F005','A'),
('SEC005','MGT101','FA25','R07','F007','A'),
-- Spring 2026 (SP26): Cohort 1 progression
('SEC006','CS212' ,'SP26','R03','F002','A'),
('SEC007','CS220' ,'SP26','R01','F003','A'),
('SEC008','ME201' ,'SP26','R05','F006','A'),
('SEC009','FIN201','SP26','R08','F008','A'),
-- Fall 2026 (FA26): Cohort 2 intro + Cohort 1 upper-level
('SEC010','CS118' ,'FA26','R03','F001','A'),
('SEC011','CS118' ,'FA26','R04','F004','B'),
('SEC012','SE210' ,'FA26','R01','F003','A'),
('SEC013','CE201' ,'FA26','R10','F010','A'),
('SEC014','AR101' ,'FA26','R09','F009','A'),
('SEC015','BS201' ,'FA26','R11','F011','A'),
('SEC016','CS330' ,'FA26','R01','F002','A'),
('SEC017','CS440' ,'FA26','R03','F001','A');

-- 16. enrollment ---------------------------------------------------------
-- Grade NULL = still in progress; grade set = section completed.
INSERT INTO enrollment (student_id, section_id, attendance_percentage, grade) VALUES
-- Fall 2025 (completed)
('S001','SEC001',92.50,'A'),
('S002','SEC001',89.00,'B+'),
('S005','SEC002',85.50,'B'),
('S002','SEC003',94.00,'A'),
('S003','SEC004',90.00,'A-'),
('S004','SEC005',95.00,'A'),
-- Spring 2026 (completed)
('S001','SEC006',91.00,'A-'),
('S005','SEC006',88.50,'B+'),
('S002','SEC007',93.00,'A-'),
('S001','SEC007',87.00,'B+'),
('S003','SEC008',89.50,'B+'),
('S004','SEC009',94.50,'A'),
-- Fall 2026 (in progress — grade NULL)
('S006','SEC010',NULL,NULL),
('S007','SEC011',NULL,NULL),
('S008','SEC013',NULL,NULL),
('S009','SEC014',NULL,NULL),
('S010','SEC015',NULL,NULL),
('S006','SEC012',NULL,NULL),
('S007','SEC012',NULL,NULL),
('S001','SEC016',NULL,NULL),
('S002','SEC016',NULL,NULL),
('S005','SEC017',NULL,NULL),
('S001','SEC017',NULL,NULL),
('S004','SEC010',NULL,NULL),
('S008','SEC010',NULL,NULL),
('S009','SEC012',NULL,NULL),
('S010','SEC010',NULL,NULL),
('S003','SEC016',NULL,NULL),
('S008','SEC012',NULL,NULL),
('S006','SEC017',NULL,NULL);

-- =============================================================================
-- VIEWS
-- =============================================================================

-- Per-enrollment transcript row. The student carries program_id and
-- applicant_id directly, so the join graph is simpler than in a
-- fully-normalized variant that would reach them through application.
CREATE VIEW student_transcript AS
SELECT
    s.student_id,
    s.full_name,
    pr.program_id,
    pr.program_name,
    c.course_code,
    c.course_title,
    t.term_name,
    t.academic_year,
    e.grade,
    e.attendance_percentage
FROM student     s
JOIN program     pr  ON pr.program_id  = s.program_id
JOIN enrollment  e   ON e.student_id   = s.student_id
JOIN section     sec ON sec.section_id = e.section_id
JOIN course      c   ON c.course_code  = sec.course_code
JOIN term        t   ON t.term_id      = sec.term_id;

-- Per-classroom occupancy: how many scheduled sections each room hosts
-- across every term.
CREATE VIEW classroom_utilization AS
SELECT
    cr.classroom_id,
    cr.building,
    cr.room_number,
    cr.capacity,
    COUNT(sec.section_id) AS sections_hosted
FROM classroom cr
LEFT JOIN section sec ON sec.classroom_id = cr.classroom_id
GROUP BY cr.classroom_id, cr.building, cr.room_number, cr.capacity;

-- =============================================================================
-- STORED PROCEDURES AND FUNCTIONS
-- =============================================================================

DELIMITER //

-- Procedure: atomically accept an admission offer by inserting the student
-- row. The auto_update_application_status trigger promotes the matching
-- application from 'Selected' to 'Enrolled' and flips the offer from 'Issued'
-- to 'Accepted'. The whole thing is wrapped in a transaction; any failure
-- rolls back.
CREATE PROCEDURE accept_admission(
    IN p_student_id       VARCHAR(15),
    IN p_program_id       VARCHAR(15),
    IN p_applicant_id     VARCHAR(15),
    IN p_full_name        VARCHAR(100),
    IN p_email            VARCHAR(100),
    IN p_enrollment_date  DATE
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO student
        (student_id, program_id, applicant_id, full_name, email,
         current_semester, enrollment_date, gpa)
    VALUES
        (p_student_id, p_program_id, p_applicant_id, p_full_name, p_email,
         1, p_enrollment_date, NULL);

    COMMIT;
END //

-- Procedure: move a student from one section to another within a term,
-- preserving attendance_percentage. Demonstrates a multi-step transaction:
-- read attendance -> delete old enrollment -> insert new enrollment. If the
-- new section is full, enforce_class_capacity raises SIGNAL; the EXIT HANDLER
-- ROLLBACKs the DELETE so the student is not left unregistered.
CREATE PROCEDURE transfer_student_to_section(
    IN p_student_id    VARCHAR(15),
    IN p_from_section  VARCHAR(20),
    IN p_to_section    VARCHAR(20)
)
BEGIN
    DECLARE v_attendance DECIMAL(5,2);
    DECLARE v_grade      ENUM('A','A-','B+','B','B-','C+','C','C-','D+','D','F');
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT attendance_percentage, grade
      INTO v_attendance, v_grade
      FROM enrollment
     WHERE student_id = p_student_id
       AND section_id = p_from_section;

    DELETE FROM enrollment
     WHERE student_id = p_student_id
       AND section_id = p_from_section;

    INSERT INTO enrollment
        (student_id, section_id, attendance_percentage, grade)
    VALUES
        (p_student_id, p_to_section, v_attendance, v_grade);

    COMMIT;
END //

-- Function: is this applicant eligible for an Engineering program?
-- Eligibility = scored >= 140 on at least one Engineering-type NET.
CREATE FUNCTION is_eligible_for_engineering(p_applicant_id VARCHAR(15))
RETURNS BOOLEAN
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_max_score DECIMAL(5,2);

    SELECT MAX(ta.score) INTO v_max_score
      FROM test_attempt ta
      JOIN entry_test et ON et.test_id = ta.test_id
     WHERE ta.applicant_id = p_applicant_id
       AND et.test_type    = 'Engineering';

    RETURN (v_max_score >= 140);
END //

DELIMITER ;

-- =============================================================================
-- TRANSACTION HANDLING EXAMPLES
-- =============================================================================
-- Two realistic multi-step transactions with ROLLBACK on failure. Both are
-- commented out so rerunning NUST.sql does not mutate seed data; uncomment to
-- exercise interactively against a fresh load of the schema.
--
-- -------------------------------------------------------------------------
-- Example 1 — Admission acceptance (happy path + rollback on failure).
-- -------------------------------------------------------------------------
-- Business scenario: applicant Sara (application AP020, status='Selected')
-- accepts her BBA offer. Inserting the student row fires
-- auto_update_application_status, promoting AP020 to 'Enrolled' and flipping
-- OF012 to 'Accepted'. If the insert fails (duplicate CNIC, orphan applicant,
-- etc.) the whole transaction rolls back — no orphan student, no drift in
-- application / offer status.
--
-- START TRANSACTION;
--   INSERT INTO student
--     (student_id, program_id, applicant_id, full_name, email,
--      current_semester, enrollment_date, gpa)
--   VALUES
--     ('S011','BBA','A0015','Sara Khan',
--      'sara.khan@student.nust.edu.pk',1,'2026-09-01',NULL);
--
--   -- If anything above raised, issue: ROLLBACK;
-- COMMIT;
--
-- Equivalent single-call form using the stored procedure above:
--   CALL accept_admission('S011','BBA','A0015','Sara Khan',
--                         'sara.khan@student.nust.edu.pk','2026-09-01');
--
-- -------------------------------------------------------------------------
-- Example 2 — Section transfer with capacity check (rollback demo).
-- -------------------------------------------------------------------------
-- Business scenario: student S001 wants to move from SEC010 (CS118, FA26)
-- into a section that's already full. The INSERT will fire the
-- enforce_class_capacity trigger, which raises SQLSTATE 45000. The DELETE of
-- the old enrollment must then be undone so the student is not left without
-- a seat in CS118. This is exactly what transfer_student_to_section's
-- EXIT HANDLER does — but the raw statements are shown here for clarity:
--
-- START TRANSACTION;
--   -- Capture current attendance so it is preserved across the move.
--   SELECT attendance_percentage INTO @att
--     FROM enrollment
--    WHERE student_id = 'S001' AND section_id = 'SEC010';
--
--   DELETE FROM enrollment
--    WHERE student_id = 'S001' AND section_id = 'SEC010';
--
--   -- If this INSERT raises (capacity reached, unknown section, etc.):
--   --   ROLLBACK;  -- restores the DELETE above
--   -- Otherwise:
--   INSERT INTO enrollment
--     (student_id, section_id, attendance_percentage, grade)
--   VALUES
--     ('S001','SEC011',@att,NULL);
-- COMMIT;
--
-- Equivalent single-call form:
--   CALL transfer_student_to_section('S001','SEC010','SEC011');
