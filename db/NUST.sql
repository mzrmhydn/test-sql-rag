-- =============================================================================
-- NUST University Database - MySQL 8.0+ Schema + Seed Data
-- =============================================================================
-- A normalized relational schema for NUST spanning:
--   * Admissions : Applicant -> EntryTest -> Application -> ApplicationFee
--   * Academics  : Student   -> Enrollment <- Section -> Course
--
-- KEY DESIGN DECISIONS
-- 1. Student is 1:1 with an accepted Application. Applicant and Program are
--    reached THROUGH Application (no denormalization on Student).
-- 2. Course is owned by a School, not a Program. Program<->Course is a real
--    M:N relationship captured in the ProgramCourse junction (with Core/Elective
--    and Semester attributes).
-- 3. Unified Fee ledger. A single Fee table tracks both the per-application
--    processing fee (paid by the Applicant via Application) and the per-student
--    tuition/hostel/library fees (paid by the Student). The payer is pinned by
--    FeeType with an XOR CHECK: exactly one of (ApplicationID, StudentID) is
--    non-NULL per row. A UNIQUE index on ApplicationID enforces "at most one
--    Application fee per Application" (MySQL treats multiple NULLs as distinct
--    in UNIQUE indexes, so non-application rows with NULL ApplicationID are
--    unaffected).
-- 4. Enrollment separates Grade (nullable) from Status (InProgress/Completed/
--    Withdrawn) instead of overloading one Grade column with sentinel values.
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TRIGGER IF EXISTS AutoUpdateApplicationStatus;
DROP TRIGGER IF EXISTS EnforceClassCapacity;
DROP VIEW  IF EXISTS ClassroomUtilization;
DROP VIEW  IF EXISTS StudentTranscript;
DROP TABLE IF EXISTS Enrollment;
DROP TABLE IF EXISTS Section;
DROP TABLE IF EXISTS Classroom;
DROP TABLE IF EXISTS Term;
DROP TABLE IF EXISTS ProgramCourse;
DROP TABLE IF EXISTS Course;
DROP TABLE IF EXISTS Instructor;
DROP TABLE IF EXISTS Fee;
DROP TABLE IF EXISTS Student;
DROP TABLE IF EXISTS Application;
DROP TABLE IF EXISTS TestScore;
DROP TABLE IF EXISTS EntryTest;
DROP TABLE IF EXISTS Applicant;
DROP TABLE IF EXISTS Program;
DROP TABLE IF EXISTS School;

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- ADMINISTRATIVE STRUCTURE
-- =============================================================================

CREATE TABLE School (
    SchoolID        INT          NOT NULL AUTO_INCREMENT,
    Name            VARCHAR(100) NOT NULL,
    Location        VARCHAR(100),
    EstablishedYear INT,
    PRIMARY KEY (SchoolID),
    UNIQUE KEY UQ_School_Name (Name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- School 1 -> M Program (mandatory: every program belongs to exactly one school)
CREATE TABLE Program (
    ProgramID     INT         NOT NULL AUTO_INCREMENT,
    SchoolID      INT         NOT NULL,
    ProgramName   VARCHAR(100) NOT NULL,
    DegreeType    VARCHAR(20)  NOT NULL,
    DurationYears INT          DEFAULT 4,
    TotalSeats    INT,
    PRIMARY KEY (ProgramID),
    UNIQUE KEY UQ_Program_School_Name (SchoolID, ProgramName),
    CONSTRAINT CHK_Program_Duration CHECK (DurationYears BETWEEN 1 AND 7),
    CONSTRAINT CHK_Program_Seats    CHECK (TotalSeats > 0),
    FOREIGN KEY (SchoolID) REFERENCES School(SchoolID) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- ADMISSIONS PIPELINE
-- =============================================================================

CREATE TABLE Applicant (
    ApplicantID     INT          NOT NULL AUTO_INCREMENT,
    FirstName       VARCHAR(50)  NOT NULL,
    LastName        VARCHAR(50)  NOT NULL,
    Email           VARCHAR(100) NOT NULL,
    Phone           VARCHAR(20),
    DOB             DATE,
    HighSchoolMarks INT,
    City            VARCHAR(50),
    PRIMARY KEY (ApplicantID),
    UNIQUE KEY UQ_Applicant_Email (Email),
    CONSTRAINT CHK_Applicant_Marks CHECK (HighSchoolMarks BETWEEN 0 AND 1100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE EntryTest (
    TestID     INT         NOT NULL AUTO_INCREMENT,
    SeriesName VARCHAR(80) NOT NULL,
    TestDate   DATE        NOT NULL,
    TestType   VARCHAR(30) NOT NULL,
    PRIMARY KEY (TestID),
    UNIQUE KEY UQ_EntryTest_Series (SeriesName),
    CONSTRAINT CHK_EntryTest_Type CHECK (TestType IN ('Engineering','Business','Architecture','Biosciences','Chemical'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction: Applicant M <-> M EntryTest
CREATE TABLE TestScore (
    TestScoreID INT NOT NULL AUTO_INCREMENT,
    ApplicantID INT NOT NULL,
    TestID      INT NOT NULL,
    Score       INT NOT NULL,
    PRIMARY KEY (TestScoreID),
    UNIQUE KEY UQ_TestScore_Applicant_Test (ApplicantID, TestID),
    CONSTRAINT CHK_TestScore_Score CHECK (Score BETWEEN 0 AND 200),
    FOREIGN KEY (ApplicantID) REFERENCES Applicant(ApplicantID) ON DELETE CASCADE,
    FOREIGN KEY (TestID)      REFERENCES EntryTest(TestID)      ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction (with attrs): Applicant M <-> M Program
CREATE TABLE Application (
    ApplicationID   INT         NOT NULL AUTO_INCREMENT,
    ApplicantID     INT         NOT NULL,
    ProgramID       INT         NOT NULL,
    ApplicationDate DATE        NOT NULL,
    Preference      INT         DEFAULT 1,
    Status          VARCHAR(20) DEFAULT 'Pending',
    PRIMARY KEY (ApplicationID),
    UNIQUE KEY UQ_Application_Applicant_Program (ApplicantID, ProgramID),
    CONSTRAINT CHK_Application_Preference CHECK (Preference BETWEEN 1 AND 5),
    CONSTRAINT CHK_Application_Status     CHECK (Status IN ('Pending','Selected','Waitlisted','Rejected','Enrolled','Declined')),
    FOREIGN KEY (ApplicantID) REFERENCES Applicant(ApplicantID) ON DELETE CASCADE,
    FOREIGN KEY (ProgramID)   REFERENCES Program(ProgramID)     ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Application 1 <-> 0..1 Student
-- The Student row exists only for the ONE accepted Application of an applicant.
-- Applicant and Program are derived through Application (no denormalization).
CREATE TABLE Student (
    StudentID      INT         NOT NULL AUTO_INCREMENT,
    ApplicationID  INT         NOT NULL,
    EnrollmentDate DATE        NOT NULL,
    CGPA           DECIMAL(4,2) DEFAULT 0.00,
    Status         VARCHAR(20)  DEFAULT 'Active',
    PRIMARY KEY (StudentID),
    UNIQUE KEY UQ_Student_Application (ApplicationID),
    CONSTRAINT CHK_Student_CGPA   CHECK (CGPA BETWEEN 0.00 AND 4.00),
    CONSTRAINT CHK_Student_Status CHECK (Status IN ('Active','Graduated','Suspended','Withdrawn')),
    FOREIGN KEY (ApplicationID) REFERENCES Application(ApplicationID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Unified Fee ledger
--   FeeType = 'Application' : paid by the applicant, keyed to Application
--                             (at most one such row per Application)
--   FeeType IN ('Tuition','Hostel','Library') : paid by the student,
--                             keyed to Student (many rows per Student)
-- The XOR CHECK guarantees exactly one payer FK is set per row.
-- The UNIQUE KEY on ApplicationID enforces "at most one Application-type fee
-- per Application"; MySQL allows multiple NULLs in a UNIQUE index, so student-
-- fee rows (ApplicationID IS NULL) are unaffected.
CREATE TABLE Fee (
    FeeID         INT           NOT NULL AUTO_INCREMENT,
    ApplicationID INT,
    StudentID     INT,
    FeeType       VARCHAR(20)   NOT NULL,
    Amount        DECIMAL(10,2) NOT NULL,
    PaymentDate   DATE          NOT NULL,
    Method        VARCHAR(20)   NOT NULL,
    PRIMARY KEY (FeeID),
    UNIQUE KEY IDX_Fee_OneAppFeePerApp (ApplicationID),
    CONSTRAINT CHK_Fee_Type   CHECK (FeeType IN ('Application','Tuition','Hostel','Library')),
    CONSTRAINT CHK_Fee_Amount CHECK (Amount >= 0),
    CONSTRAINT CHK_Fee_Method CHECK (Method IN ('Bank','Online','Cheque','Cash')),
    CONSTRAINT CHK_Fee_Payer  CHECK (
        (FeeType = 'Application'
            AND ApplicationID IS NOT NULL AND StudentID IS NULL)
     OR (FeeType IN ('Tuition','Hostel','Library')
            AND StudentID IS NOT NULL AND ApplicationID IS NULL)
    ),
    FOREIGN KEY (ApplicationID) REFERENCES Application(ApplicationID) ON DELETE CASCADE,
    FOREIGN KEY (StudentID)     REFERENCES Student(StudentID)         ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- ACADEMIC PIPELINE
-- =============================================================================

CREATE TABLE Instructor (
    InstructorID INT          NOT NULL AUTO_INCREMENT,
    SchoolID     INT          NOT NULL,
    FirstName    VARCHAR(50)  NOT NULL,
    LastName     VARCHAR(50)  NOT NULL,
    Title        VARCHAR(50)  NOT NULL,
    Email        VARCHAR(100),
    HireDate     DATE,
    PRIMARY KEY (InstructorID),
    UNIQUE KEY UQ_Instructor_Email (Email),
    CONSTRAINT CHK_Instructor_Title CHECK (Title IN ('Lecturer','Assistant Professor','Associate Professor','Professor')),
    FOREIGN KEY (SchoolID) REFERENCES School(SchoolID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Course is owned by a School (a teaching unit), NOT a Program.
-- This enables multiple programs to share the same course.
CREATE TABLE Course (
    CourseID   INT          NOT NULL AUTO_INCREMENT,
    SchoolID   INT          NOT NULL,
    CourseCode VARCHAR(10)  NOT NULL,
    CourseName VARCHAR(100) NOT NULL,
    Credits    INT          NOT NULL,
    PRIMARY KEY (CourseID),
    UNIQUE KEY UQ_Course_Code (CourseCode),
    CONSTRAINT CHK_Course_Credits CHECK (Credits BETWEEN 1 AND 6),
    FOREIGN KEY (SchoolID) REFERENCES School(SchoolID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction: Program M <-> M Course
CREATE TABLE ProgramCourse (
    ProgramID  INT         NOT NULL,
    CourseID   INT         NOT NULL,
    CourseType VARCHAR(10) NOT NULL DEFAULT 'Core',
    Semester   INT         NOT NULL,
    PRIMARY KEY (ProgramID, CourseID),
    CONSTRAINT CHK_ProgramCourse_Type     CHECK (CourseType IN ('Core','Elective')),
    CONSTRAINT CHK_ProgramCourse_Semester CHECK (Semester BETWEEN 1 AND 10),
    FOREIGN KEY (ProgramID) REFERENCES Program(ProgramID) ON DELETE CASCADE,
    FOREIGN KEY (CourseID)  REFERENCES Course(CourseID)   ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Term (
    TermID    INT         NOT NULL AUTO_INCREMENT,
    TermName  VARCHAR(50) NOT NULL,
    StartDate DATE        NOT NULL,
    EndDate   DATE        NOT NULL,
    PRIMARY KEY (TermID),
    UNIQUE KEY UQ_Term_Name (TermName),
    CONSTRAINT CHK_Term_Dates CHECK (EndDate > StartDate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Classroom (
    ClassroomID INT         NOT NULL AUTO_INCREMENT,
    SchoolID    INT         NOT NULL,
    RoomNumber  VARCHAR(20) NOT NULL,
    Capacity    INT         NOT NULL,
    RoomType    VARCHAR(20) NOT NULL,
    PRIMARY KEY (ClassroomID),
    UNIQUE KEY UQ_Classroom_School_Room (SchoolID, RoomNumber),
    CONSTRAINT CHK_Classroom_Capacity CHECK (Capacity > 0),
    CONSTRAINT CHK_Classroom_RoomType CHECK (RoomType IN ('Lecture','Lab','Studio','Hall')),
    FOREIGN KEY (SchoolID) REFERENCES School(SchoolID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A Section is a scheduled offering of a Course, in a Term, taught by an
-- Instructor, in a Classroom. All four links are mandatory.
CREATE TABLE Section (
    SectionID    INT         NOT NULL AUTO_INCREMENT,
    CourseID     INT         NOT NULL,
    TermID       INT         NOT NULL,
    InstructorID INT         NOT NULL,
    ClassroomID  INT         NOT NULL,
    SectionName  VARCHAR(10) NOT NULL,
    PRIMARY KEY (SectionID),
    UNIQUE KEY UQ_Section_Course_Term_Name (CourseID, TermID, SectionName),
    FOREIGN KEY (CourseID)     REFERENCES Course(CourseID),
    FOREIGN KEY (TermID)       REFERENCES Term(TermID),
    FOREIGN KEY (InstructorID) REFERENCES Instructor(InstructorID),
    FOREIGN KEY (ClassroomID)  REFERENCES Classroom(ClassroomID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Junction: Student M <-> M Section
CREATE TABLE Enrollment (
    EnrollmentID INT         NOT NULL AUTO_INCREMENT,
    StudentID    INT         NOT NULL,
    SectionID    INT         NOT NULL,
    Grade        VARCHAR(2),
    Status       VARCHAR(15) NOT NULL DEFAULT 'InProgress',
    PRIMARY KEY (EnrollmentID),
    UNIQUE KEY UQ_Enrollment_Student_Section (StudentID, SectionID),
    CONSTRAINT CHK_Enrollment_Grade  CHECK (Grade IS NULL OR
               Grade IN ('A','A-','B+','B','B-','C+','C','C-','D+','D','F')),
    CONSTRAINT CHK_Enrollment_Status CHECK (Status IN ('InProgress','Completed','Withdrawn')),
    CONSTRAINT CHK_Enrollment_GradeStatus CHECK (
        (Status = 'Completed'                    AND Grade IS NOT NULL)
     OR (Status IN ('InProgress','Withdrawn')    AND Grade IS NULL)
    ),
    FOREIGN KEY (StudentID) REFERENCES Student(StudentID),
    FOREIGN KEY (SectionID) REFERENCES Section(SectionID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- TRIGGERS
-- =============================================================================

DELIMITER //

-- Reject enrollments that would exceed the hosting classroom's capacity.
CREATE TRIGGER EnforceClassCapacity
BEFORE INSERT ON Enrollment
FOR EACH ROW
BEGIN
    DECLARE v_current_count INT;
    DECLARE v_capacity       INT;

    SELECT COUNT(*) INTO v_current_count
    FROM Enrollment
    WHERE SectionID = NEW.SectionID;

    SELECT c.Capacity INTO v_capacity
    FROM Classroom c
    JOIN Section   s ON s.ClassroomID = c.ClassroomID
    WHERE s.SectionID = NEW.SectionID;

    IF v_current_count >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Enrollment failed: Classroom capacity reached.';
    END IF;
END //

-- When a Student is created, promote the corresponding accepted Application
-- from 'Selected' to 'Enrolled'. Sibling applications of the same applicant
-- are untouched.
CREATE TRIGGER AutoUpdateApplicationStatus
AFTER INSERT ON Student
FOR EACH ROW
BEGIN
    UPDATE Application
       SET Status = 'Enrolled'
     WHERE ApplicationID = NEW.ApplicationID
       AND Status        = 'Selected';
END //

DELIMITER ;

-- =============================================================================
-- INDEXES
-- =============================================================================

CREATE INDEX IDX_Enrollment_Student   ON Enrollment(StudentID);
CREATE INDEX IDX_Section_Course       ON Section(CourseID);
CREATE INDEX IDX_Section_Term         ON Section(TermID);
CREATE INDEX IDX_Section_Instructor   ON Section(InstructorID);
CREATE INDEX IDX_Application_Status   ON Application(Status);
CREATE INDEX IDX_Application_Program  ON Application(ProgramID);
CREATE INDEX IDX_TestScore_Test       ON TestScore(TestID);
CREATE INDEX IDX_Course_School        ON Course(SchoolID);
CREATE INDEX IDX_ProgramCourse_Course ON ProgramCourse(CourseID);
CREATE INDEX IDX_Fee_Student          ON Fee(StudentID);
CREATE INDEX IDX_Fee_Type             ON Fee(FeeType);

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- 1. School --------------------------------------------------------------------
INSERT INTO School (Name, Location, EstablishedYear) VALUES
('SEECS','H-12 Islamabad',2008),   -- 1
('SMME' ,'H-12 Islamabad',2008),   -- 2
('NBS'  ,'H-12 Islamabad',2005),   -- 3
('SADA' ,'H-12 Islamabad',2010),   -- 4
('NICE' ,'H-12 Islamabad',2006),   -- 5
('S3H'  ,'H-12 Islamabad',2010),   -- 6
('ASAB' ,'H-12 Islamabad',2005),   -- 7
('SCME' ,'H-12 Islamabad',2009),   -- 8
('CAMP' ,'H-12 Islamabad',2007),   -- 9
('MCS'  ,'Rawalpindi'    ,2002);   -- 10

-- 2. Program -------------------------------------------------------------------
INSERT INTO Program (SchoolID, ProgramName, DegreeType, DurationYears, TotalSeats) VALUES
(1,'Software Engineering'    ,'BESE'  ,4,120),  -- 1
(1,'Computer Science'        ,'BSCS'  ,4,150),  -- 2
(2,'Mechanical Engineering'  ,'BME'   ,4,100),  -- 3
(3,'Business Administration' ,'BBA'   ,4,120),  -- 4
(3,'Accounting and Finance'  ,'BSAF'  ,4, 80),  -- 5
(5,'Civil Engineering'       ,'BECE'  ,4,100),  -- 6
(7,'Applied Biosciences'     ,'BSAB'  ,4, 60),  -- 7
(8,'Chemical Engineering'    ,'BChemE',4, 80),  -- 8
(4,'Architecture'            ,'BArch' ,5, 50),  -- 9
(1,'Information Security'    ,'MSIS'  ,2, 40),  -- 10
(1,'Electrical Engineering'  ,'BEE'   ,4,120),  -- 11
(2,'Industrial Engineering'  ,'BIME'  ,4, 60);  -- 12

-- 3. Applicant -----------------------------------------------------------------
INSERT INTO Applicant (FirstName, LastName, Email, Phone, DOB, HighSchoolMarks, City) VALUES
('Ali'   ,'Khan'   ,'ali.khan@test.com'     ,'03001234567','2006-04-12', 980,'Islamabad'),   -- 1
('Aisha' ,'Ahmed'  ,'aisha.ahmed@test.com'  ,'03011234567','2006-09-01',1010,'Lahore'),      -- 2
('Bilal' ,'Tariq'  ,'bilal.tariq@test.com'  ,'03021234567','2006-11-20', 880,'Karachi'),     -- 3
('Fatima','Zahra'  ,'fatima.zahra@test.com' ,'03331234567','2006-02-15', 950,'Islamabad'),   -- 4
('Saad'  ,'Hussain','saad.hussain@test.com' ,'03451234567','2005-06-30', 905,'Peshawar'),    -- 5
('Omar'  ,'Sheikh' ,'omar.sheikh@test.com'  ,'03111234567','2007-08-08', 850,'Multan'),      -- 6
('Zainab','Rizvi'  ,'zainab.rizvi@test.com' ,'03441234567','2007-01-25',1020,'Islamabad'),   -- 7
('Hamza' ,'Farooq' ,'hamza.farooq@test.com' ,'03211234567','2007-03-10', 800,'Faisalabad'),  -- 8
('Sana'  ,'Iqbal'  ,'sana.iqbal@test.com'   ,'03311234567','2007-07-22', 940,'Rawalpindi'),  -- 9
('Usman' ,'Ali'    ,'usman.ali@test.com'    ,'03121234567','2007-12-05', 860,'Quetta'),      -- 10
('Hina'  ,'Malik'  ,'hina.malik@test.com'   ,'03131234567','2007-04-18', 970,'Lahore'),      -- 11
('Tariq' ,'Mahmood','tariq.mahmood@test.com','03041234567','2007-05-22', 830,'Karachi'),     -- 12
('Noor'  ,'Fatima' ,'noor.fatima@test.com'  ,'03511234567','2007-10-30', 960,'Islamabad'),   -- 13
('Ahmed' ,'Raza'   ,'ahmed.raza@test.com'   ,'03061234567','2007-09-14', 790,'Hyderabad'),   -- 14
('Sara'  ,'Khan'   ,'sara.khan@test.com'    ,'03561234567','2007-06-02', 890,'Lahore');      -- 15

-- 4. EntryTest -----------------------------------------------------------------
INSERT INTO EntryTest (SeriesName, TestDate, TestType) VALUES
('NET-1 (2025 intake)'   ,'2024-12-15','Engineering'),  -- 1
('NET-2 (2025 intake)'   ,'2025-02-20','Engineering'),  -- 2
('NET-3 (2025 intake)'   ,'2025-04-10','Engineering'),  -- 3
('NBS NET (2025 intake)' ,'2025-04-25','Business'),     -- 4
('NET-1 (2026 intake)'   ,'2025-12-15','Engineering'),  -- 5
('NET-2 (2026 intake)'   ,'2026-02-20','Engineering'),  -- 6
('NET-3 (2026 intake)'   ,'2026-04-10','Engineering'),  -- 7
('NBS NET (2026 intake)' ,'2026-04-25','Business'),     -- 8
('SADA NET (2026 intake)','2026-05-10','Architecture'), -- 9
('ASAB NET (2026 intake)','2026-05-20','Biosciences');  -- 10

-- 5. TestScore -----------------------------------------------------------------
INSERT INTO TestScore (ApplicantID, TestID, Score) VALUES
( 1, 2,145), ( 1, 3,155),       -- Ali   (2025)
( 2, 2,162), ( 2, 3,168),       -- Aisha (2025)
( 3, 1,135), ( 3, 3,140),       -- Bilal (2025)
( 4, 4,155),                    -- Fatima(2025, Bus)
( 5, 2,140), ( 5, 3,138),       -- Saad  (2025)
( 6, 8,125),                    -- Omar  (2026, Bus)
( 7, 6,172), ( 7, 7,175),       -- Zainab(2026)
( 8, 7,110),                    -- Hamza (2026)
( 9, 6,148), ( 9, 7,152),       -- Sana  (2026)
(10, 6,142), (10, 7,145),       -- Usman (2026)
(11, 9,160),                    -- Hina  (2026, Arch)
(12, 6,130), (12, 7,125),       -- Tariq (2026)
(13,10,155),                    -- Noor  (2026, Bio)
(14, 7,115),                    -- Ahmed (2026)
(15, 8,130);                    -- Sara  (2026, Bus)

-- 6. Application (20 rows) -----------------------------------------------------
-- Rows with Status='Selected' will be auto-promoted to 'Enrolled' by the
-- AutoUpdateApplicationStatus trigger once a Student row references them.
INSERT INTO Application (ApplicantID, ProgramID, ApplicationDate, Preference, Status) VALUES
( 1, 2,'2025-07-01',1,'Selected'),    -- 1  Ali    -> BSCS
( 2, 1,'2025-07-01',1,'Selected'),    -- 2  Aisha  -> BESE
( 2, 2,'2025-07-01',2,'Waitlisted'),  -- 3  Aisha  -> BSCS
( 3, 3,'2025-07-01',1,'Selected'),    -- 4  Bilal  -> BME
( 4, 4,'2025-07-02',1,'Selected'),    -- 5  Fatima -> BBA
( 5, 2,'2025-07-05',1,'Selected'),    -- 6  Saad   -> BSCS
( 5,11,'2025-07-05',2,'Waitlisted'),  -- 7  Saad   -> BEE
( 6, 5,'2026-07-01',1,'Selected'),    -- 8  Omar   -> BSAF  (accepted, not yet a Student)
( 7, 1,'2026-07-01',1,'Selected'),    -- 9  Zainab -> BESE
( 7, 2,'2026-07-01',2,'Rejected'),    -- 10 Zainab -> BSCS
( 8, 8,'2026-07-02',1,'Rejected'),    -- 11 Hamza  -> BChemE
( 9, 2,'2026-07-05',1,'Selected'),    -- 12 Sana   -> BSCS
( 9, 1,'2026-07-05',2,'Rejected'),    -- 13 Sana   -> BESE
(10, 6,'2026-07-07',1,'Selected'),    -- 14 Usman  -> BECE
(11, 9,'2026-07-08',1,'Selected'),    -- 15 Hina   -> BArch
(11, 7,'2026-07-08',2,'Rejected'),    -- 16 Hina   -> BSAB
(12, 2,'2026-07-10',1,'Waitlisted'),  -- 17 Tariq  -> BSCS
(13, 7,'2026-07-12',1,'Selected'),    -- 18 Noor   -> BSAB
(14, 3,'2026-07-15',1,'Rejected'),    -- 19 Ahmed  -> BME
(15, 4,'2026-07-18',1,'Selected');    -- 20 Sara   -> BBA   (accepted, not yet a Student)

-- 7. Student (10 rows) ---------------------------------------------------------
-- Inserting a Student fires AutoUpdateApplicationStatus, promoting the
-- referenced Application from 'Selected' to 'Enrolled'.
INSERT INTO Student (ApplicationID, EnrollmentDate, CGPA, Status) VALUES
( 1,'2025-09-01',3.58,'Active'),  -- S1  Ali    (BSCS, via App 1)
( 2,'2025-09-01',3.67,'Active'),  -- S2  Aisha  (BESE, via App 2)
( 4,'2025-09-01',3.50,'Active'),  -- S3  Bilal  (BME,  via App 4)
( 5,'2025-09-01',4.00,'Active'),  -- S4  Fatima (BBA,  via App 5)
( 6,'2025-09-01',3.15,'Active'),  -- S5  Saad   (BSCS, via App 6)
( 9,'2026-09-01',0.00,'Active'),  -- S6  Zainab (BESE, via App 9)
(12,'2026-09-01',0.00,'Active'),  -- S7  Sana   (BSCS, via App 12)
(14,'2026-09-01',0.00,'Active'),  -- S8  Usman  (BECE, via App 14)
(15,'2026-09-01',0.00,'Active'),  -- S9  Hina   (BArch,via App 15)
(18,'2026-09-01',0.00,'Active');  -- S10 Noor   (BSAB, via App 18)

-- 8. Fee (30 rows total)
--    15 Application fees (one per applicant, on their primary application)
--  + 15 Student fees     (10 tuition + 3 hostel + 2 library)
-- All flow through the unified Fee ledger. ApplicationID is set iff the
-- row is the processing fee; StudentID is set iff it is a tuition/hostel/
-- library charge. The XOR CHECK rejects any row that violates this.
INSERT INTO Fee (ApplicationID, StudentID, FeeType, Amount, PaymentDate, Method) VALUES
-- -- Application processing fees (paid at application time) ------------------
( 1,  NULL,'Application',4000.00,'2025-05-01','Online'),
( 2,  NULL,'Application',4000.00,'2025-05-02','Online'),
( 4,  NULL,'Application',4000.00,'2025-05-05','Bank'),
( 5,  NULL,'Application',4000.00,'2025-05-10','Online'),
( 6,  NULL,'Application',4000.00,'2025-05-12','Online'),
( 8,  NULL,'Application',4000.00,'2026-04-20','Online'),
( 9,  NULL,'Application',4000.00,'2026-04-22','Bank'),
(11,  NULL,'Application',4000.00,'2026-04-25','Online'),
(12,  NULL,'Application',4000.00,'2026-05-01','Cheque'),
(14,  NULL,'Application',4000.00,'2026-05-03','Online'),
(15,  NULL,'Application',4000.00,'2026-05-05','Online'),
(17,  NULL,'Application',4000.00,'2026-05-07','Online'),
(18,  NULL,'Application',4000.00,'2026-05-10','Bank'),
(19,  NULL,'Application',4000.00,'2026-05-12','Online'),
(20,  NULL,'Application',4000.00,'2026-05-14','Online'),
-- -- Tuition for every enrolled student --------------------------------------
(NULL, 1,'Tuition',150000.00,'2025-08-15','Bank'),
(NULL, 2,'Tuition',160000.00,'2025-08-16','Bank'),
(NULL, 3,'Tuition',140000.00,'2025-08-18','Online'),
(NULL, 4,'Tuition',120000.00,'2025-08-20','Online'),
(NULL, 5,'Tuition',150000.00,'2025-08-22','Bank'),
(NULL, 6,'Tuition',160000.00,'2026-08-15','Bank'),
(NULL, 7,'Tuition',150000.00,'2026-08-16','Online'),
(NULL, 8,'Tuition',140000.00,'2026-08-18','Bank'),
(NULL, 9,'Tuition',145000.00,'2026-08-20','Online'),
(NULL,10,'Tuition',135000.00,'2026-08-22','Online'),
-- -- Hostel fees for non-Islamabad cohort ------------------------------------
(NULL, 2,'Hostel', 55000.00,'2025-08-25','Bank'),     -- Aisha (Lahore)
(NULL, 3,'Hostel', 55000.00,'2025-08-26','Online'),   -- Bilal (Karachi)
(NULL, 9,'Hostel', 55000.00,'2026-08-25','Online'),   -- Hina  (Lahore)
-- -- Library fees ------------------------------------------------------------
(NULL, 1,'Library',  3000.00,'2025-09-10','Online'),
(NULL, 4,'Library',  3000.00,'2025-09-12','Cash');

-- 9. Instructor ----------------------------------------------------------------
INSERT INTO Instructor (SchoolID, FirstName, LastName, Title, Email, HireDate) VALUES
(1,'Arshad','Ali'    ,'Professor'          ,'arshad.ali@seecs.nust.edu.pk'   ,'2010-09-01'),
(1,'Shamim','Baig'   ,'Assistant Professor','shamim.baig@seecs.nust.edu.pk'  ,'2015-03-15'),
(1,'Faisal','Shafiq' ,'Associate Professor','faisal.shafiq@seecs.nust.edu.pk','2012-08-20'),
(1,'Noman' ,'Qadir'  ,'Lecturer'           ,'noman.qadir@seecs.nust.edu.pk'  ,'2019-01-10'),
(2,'Rizwan','Riaz'   ,'Professor'          ,'rizwan.riaz@smme.nust.edu.pk'   ,'2009-07-01'),
(2,'Ahmad' ,'Butt'   ,'Associate Professor','ahmad.butt@smme.nust.edu.pk'    ,'2014-09-01'),
(3,'Sarah' ,'Khan'   ,'Assistant Professor','sarah.khan@nbs.nust.edu.pk'     ,'2017-02-01'),
(3,'Asim'  ,'Zafar'  ,'Lecturer'           ,'asim.zafar@nbs.nust.edu.pk'     ,'2020-01-15'),
(4,'Hasan' ,'Javed'  ,'Assistant Professor','hasan.javed@sada.nust.edu.pk'   ,'2016-05-10'),
(5,'Tahir' ,'Mehmood','Professor'          ,'tahir.mehmood@nice.nust.edu.pk' ,'2008-11-01'),
(7,'Ayesha','Tariq'  ,'Associate Professor','ayesha.tariq@asab.nust.edu.pk'  ,'2013-04-12'),
(8,'Usman' ,'Ghadeer','Professor'          ,'usman.ghadeer@scme.nust.edu.pk' ,'2011-06-15');

-- 10. Course (15 rows, each owned by a School) --------------------------------
INSERT INTO Course (SchoolID, CourseCode, CourseName, Credits) VALUES
(1,'CS118' ,'Programming Fundamentals'   ,4),  -- 1
(1,'CS212' ,'Object Oriented Programming',4),  -- 2
(1,'CS220' ,'Database Systems'           ,4),  -- 3
(1,'CS330' ,'Operating Systems'          ,3),  -- 4
(1,'CS440' ,'Machine Learning'           ,3),  -- 5
(1,'SE210' ,'Software Requirements Eng'  ,3),  -- 6
(1,'SE310' ,'Software Design'            ,3),  -- 7
(2,'ME101' ,'Engineering Mechanics'      ,3),  -- 8
(2,'ME201' ,'Thermodynamics'             ,3),  -- 9
(3,'MGT101','Principles of Management'   ,3),  -- 10
(3,'FIN201','Financial Accounting'       ,3),  -- 11
(5,'CE201' ,'Circuit Analysis'           ,3),  -- 12
(4,'AR101' ,'Architecture Studio I'      ,4),  -- 13
(7,'BS201' ,'Microbiology'               ,3),  -- 14
(8,'CHE201','Mass Transfer'              ,3);  -- 15

-- 11. ProgramCourse (M:N mapping: a single course appears in many programs) ---
INSERT INTO ProgramCourse (ProgramID, CourseID, CourseType, Semester) VALUES
-- CS118 Programming Fundamentals: shared across all computing/engineering programs
( 2, 1,'Core'    ,1),   -- BSCS
( 1, 1,'Core'    ,1),   -- BESE
(11, 1,'Core'    ,1),   -- BEE
-- CS212 OOP
( 2, 2,'Core'    ,2),   -- BSCS
( 1, 2,'Core'    ,2),   -- BESE
-- CS220 Databases
( 2, 3,'Core'    ,4),   -- BSCS
( 1, 3,'Core'    ,3),   -- BESE
-- CS330 OS
( 2, 4,'Core'    ,5),   -- BSCS
( 1, 4,'Elective',6),   -- BESE
-- CS440 ML
( 2, 5,'Elective',7),   -- BSCS
-- SE210 Requirements
( 1, 6,'Core'    ,3),   -- BESE
( 2, 6,'Elective',6),   -- BSCS
-- SE310 Software Design
( 1, 7,'Core'    ,5),   -- BESE
-- ME101 Mechanics
( 3, 8,'Core'    ,1),   -- BME
(12, 8,'Core'    ,1),   -- BIME
-- ME201 Thermo
( 3, 9,'Core'    ,3),   -- BME
-- MGT101 Management
( 4,10,'Core'    ,1),   -- BBA
( 5,10,'Core'    ,1),   -- BSAF
-- FIN201 Financial Accounting
( 5,11,'Core'    ,2),   -- BSAF
( 4,11,'Core'    ,3),   -- BBA
-- CE201 Circuits
( 6,12,'Core'    ,2),   -- BECE
(11,12,'Core'    ,2),   -- BEE
-- AR101 Studio
( 9,13,'Core'    ,1),   -- BArch
-- BS201 Microbio
( 7,14,'Core'    ,2),   -- BSAB
-- CHE201 Mass Transfer
( 8,15,'Core'    ,3);   -- BChemE

-- 12. Term ---------------------------------------------------------------------
INSERT INTO Term (TermName, StartDate, EndDate) VALUES
('Fall 2024'  ,'2024-09-01','2025-01-15'),
('Spring 2025','2025-02-01','2025-06-15'),
('Summer 2025','2025-07-01','2025-08-15'),
('Fall 2025'  ,'2025-09-01','2026-01-15'),
('Spring 2026','2026-02-01','2026-06-15'),
('Summer 2026','2026-07-01','2026-08-15'),
('Fall 2026'  ,'2026-09-01','2027-01-15'),
('Spring 2027','2027-02-01','2027-06-15'),
('Fall 2027'  ,'2027-09-01','2028-01-15'),
('Spring 2028','2028-02-01','2028-06-15');

-- 13. Classroom ----------------------------------------------------------------
INSERT INTO Classroom (SchoolID, RoomNumber, Capacity, RoomType) VALUES
(1,'CR-01'    ,50,'Lecture'),   -- 1
(1,'CR-02'    ,50,'Lecture'),   -- 2
(1,'Lab-A'    ,40,'Lab'),       -- 3
(1,'Lab-B'    ,40,'Lab'),       -- 4
(2,'CR-101'   ,60,'Lecture'),   -- 5
(2,'CR-102'   ,60,'Lecture'),   -- 6
(3,'Hall-A'  ,100,'Hall'),      -- 7
(3,'CR-05'    ,40,'Lecture'),   -- 8
(4,'Studio-1' ,30,'Studio'),    -- 9
(5,'CR-Civil' ,50,'Lecture'),   -- 10
(7,'Lab-Bio'  ,35,'Lab'),       -- 11
(8,'Lab-Chem' ,35,'Lab');       -- 12

-- 14. Section ------------------------------------------------------------------
INSERT INTO Section (CourseID, TermID, InstructorID, ClassroomID, SectionName) VALUES
-- Fall 2025 (Term 4): Cohort 1 intro
( 1,4, 1, 3,'A'),   -- 1  CS118  Lab-A
( 1,4, 4, 4,'B'),   -- 2  CS118  Lab-B
( 6,4, 3, 1,'A'),   -- 3  SE210  CR-01
( 8,4, 5, 5,'A'),   -- 4  ME101  CR-101
(10,4, 7, 7,'A'),   -- 5  MGT101 Hall-A
-- Spring 2026 (Term 5): Cohort 1 progression
( 2,5, 2, 3,'A'),   -- 6  CS212  Lab-A
( 3,5, 3, 1,'A'),   -- 7  CS220  CR-01
( 9,5, 6, 5,'A'),   -- 8  ME201  CR-101
(11,5, 8, 8,'A'),   -- 9  FIN201 CR-05
-- Fall 2026 (Term 7): Cohort 2 intro + Cohort 1 upper-level
( 1,7, 1, 3,'A'),   -- 10 CS118  Lab-A
( 1,7, 4, 4,'B'),   -- 11 CS118  Lab-B
( 6,7, 3, 1,'A'),   -- 12 SE210  CR-01
(12,7,10,10,'A'),   -- 13 CE201  CR-Civil
(13,7, 9, 9,'A'),   -- 14 AR101  Studio-1
(14,7,11,11,'A'),   -- 15 BS201  Lab-Bio
( 4,7, 2, 1,'A'),   -- 16 CS330  CR-01
( 5,7, 1, 3,'A');   -- 17 CS440  Lab-A

-- 15. Enrollment (30 rows: history + in-progress) -----------------------------
INSERT INTO Enrollment (StudentID, SectionID, Grade, Status) VALUES
-- Fall 2025 (completed)
( 1, 1,'A'  ,'Completed'),
( 2, 1,'B+' ,'Completed'),
( 5, 2,'B'  ,'Completed'),
( 2, 3,'A'  ,'Completed'),
( 3, 4,'A-' ,'Completed'),
( 4, 5,'A'  ,'Completed'),
-- Spring 2026 (completed)
( 1, 6,'A-' ,'Completed'),
( 5, 6,'B+' ,'Completed'),
( 2, 7,'A-' ,'Completed'),
( 1, 7,'B+' ,'Completed'),
( 3, 8,'B+' ,'Completed'),
( 4, 9,'A'  ,'Completed'),
-- Fall 2026 (in progress)
( 6,10,NULL,'InProgress'),
( 7,11,NULL,'InProgress'),
( 8,13,NULL,'InProgress'),
( 9,14,NULL,'InProgress'),
(10,15,NULL,'InProgress'),
( 6,12,NULL,'InProgress'),
( 7,12,NULL,'InProgress'),
( 1,16,NULL,'InProgress'),
( 2,16,NULL,'InProgress'),
( 5,17,NULL,'InProgress'),
( 1,17,NULL,'InProgress'),
( 4,10,NULL,'InProgress'),
( 8,10,NULL,'InProgress'),
( 9,12,NULL,'InProgress'),
(10,10,NULL,'InProgress'),
( 3,16,NULL,'InProgress'),
( 8,12,NULL,'InProgress'),
( 6,17,NULL,'InProgress');

-- =============================================================================
-- VIEWS
-- =============================================================================

-- Transcript: reach Applicant/Program through Application (no denormalization)
CREATE VIEW StudentTranscript AS
SELECT
    s.StudentID,
    ap.FirstName,
    ap.LastName,
    pr.ProgramName,
    c.CourseCode,
    c.CourseName,
    t.TermName,
    e.Grade,
    e.Status AS EnrollmentStatus
FROM Student     s
JOIN Application app ON app.ApplicationID = s.ApplicationID
JOIN Applicant   ap  ON ap.ApplicantID    = app.ApplicantID
JOIN Program     pr  ON pr.ProgramID      = app.ProgramID
JOIN Enrollment  e   ON e.StudentID       = s.StudentID
JOIN Section     sec ON sec.SectionID     = e.SectionID
JOIN Course      c   ON c.CourseID        = sec.CourseID
JOIN Term        t   ON t.TermID          = sec.TermID;

CREATE VIEW ClassroomUtilization AS
SELECT
    sch.Name             AS SchoolName,
    cr.RoomNumber,
    cr.Capacity,
    cr.RoomType,
    COUNT(sec.SectionID) AS SectionsHosted
FROM Classroom cr
JOIN School sch ON sch.SchoolID = cr.SchoolID
LEFT JOIN Section sec ON sec.ClassroomID = cr.ClassroomID
GROUP BY cr.ClassroomID, sch.Name, cr.RoomNumber, cr.Capacity, cr.RoomType;
