# Phase 2 — Relational Schema Mapped from ER Diagram

---

## 1. ER Diagram Summary

The ER diagram (see [db/ERD.mmd](db/ERD.mmd)) models 16 entities across two converging pipelines:

- **Admissions pipeline:** applicant → test_attempt → entry_test; applicant → application → offer → (student)
- **Academic pipeline:** school → program / course / faculty; term → section ← classroom / faculty / course; student → enrollment → section

The two pipelines converge at **student**: an applicant who accepts an offer becomes a student, linking the admissions outcome to the academic record.

---

## 2. Relational Schema

Each relation is presented in the form:

> **TableName**(<u>primary_key</u>, attribute, ..., *foreign_key*)

Underlines denote primary key attributes; italics denote foreign keys.

---

### 2.1 Administrative Structure

**school**(<u>school_id</u>, school_name, abbreviation, established_year)
- `school_id`: human-readable code, e.g. `SEECS`, `NBS`
- `school_name` and `abbreviation` both UNIQUE
- Mapped from: `school` entity (no FKs into other entities at this level)

**faculty**(<u>faculty_id</u>, *school_id*, full_name, email, designation)
- `school_id` → school(school_id) ON DELETE CASCADE
- `designation` ∈ {Lecturer, Assistant Professor, Associate Professor, Professor}
- Maps the 1:N relationship: school **employs** faculty

**program**(<u>program_id</u>, *school_id*, program_name, degree_type, total_semesters, total_credits, total_seats)
- `school_id` → school(school_id) ON DELETE CASCADE
- `degree_type` ∈ {BS, BE, BBA, BArch, MS, PhD}
- Maps the 1:N relationship: school **offers** program

---

### 2.2 Course Catalogue and Curriculum

**course**(<u>course_code</u>, *school_id*, course_title, course_type, credit_hours, contact_hours)
- `school_id` → school(school_id)
- `course_type` ∈ {Theory, Lab, Theory+Lab, Studio, Seminar}
- Maps the 1:N relationship: school **owns** course

**prerequisite**(<u>course_code</u>, <u>prereq_course_code</u>)
- `course_code` → course(course_code) ON DELETE CASCADE
- `prereq_course_code` → course(course_code) ON DELETE CASCADE
- Composite PK = {course_code, prereq_course_code}
- CHECK (course_code ≠ prereq_course_code) prevents self-loops
- Maps the M:N reflexive relationship: course **has_prereq** course

**program_course**(<u>program_id</u>, <u>course_code</u>, recommended_semester, is_core)
- `program_id` → program(program_id) ON DELETE CASCADE
- `course_code` → course(course_code) ON DELETE CASCADE
- Composite PK = {program_id, course_code}
- Maps the M:N relationship: program **requires** course (with attributes)

---

### 2.3 Scheduling

**term**(<u>term_id</u>, term_name, academic_year, start_date, end_date)
- `term_name` ∈ {Fall, Spring, Summer}
- UNIQUE (term_name, academic_year) — no duplicate intakes
- Standalone entity; no FK dependencies upward

**classroom**(<u>classroom_id</u>, building, room_number, capacity)
- `classroom_id`: human-readable code, e.g. `SEECS-101`
- Standalone entity; capacity is the hard upper bound for enrollment trigger

**section**(<u>section_id</u>, *course_code*, *term_id*, *classroom_id*, *faculty_id*, section_label)
- `course_code` → course(course_code)
- `term_id` → term(term_id)
- `classroom_id` → classroom(classroom_id)
- `faculty_id` → faculty(faculty_id)
- UNIQUE (course_code, term_id, section_label) — prevents duplicate sections
- Maps four relationships simultaneously: term **contains** section; course **offered_as** section; classroom **hosts** section; faculty **teaches** section

---

### 2.4 Admissions Pipeline

**applicant**(<u>applicant_id</u>, full_name, cnic, email, high_school_board, high_school_score, best_test_score)
- `cnic` and `email` both UNIQUE
- `high_school_board` ∈ {FBISE, AKU-EB, Cambridge, Other}
- `best_test_score`: denormalised cache of MAX(test_attempt.score) for this applicant — updated on each attempt (trade-off discussed in Phase 2 Normalization doc)
- `high_school_score` range: 0–1100; `best_test_score` range: 0–200

**entry_test**(<u>test_id</u>, academic_year, net_number, test_type, test_date, total_marks)
- `test_type` ∈ {Engineering, CS, Business, Architecture, Biosciences, Chemical}
- UNIQUE (academic_year, net_number, test_type) — identifies a specific sitting
- `total_marks` = 200 (constant in current data)

**test_attempt**(<u>applicant_id</u>, <u>test_id</u>, score)
- `applicant_id` → applicant(applicant_id) ON DELETE CASCADE
- `test_id` → entry_test(test_id) ON DELETE CASCADE
- Composite PK = {applicant_id, test_id}
- Maps the M:N relationship: applicant **attempts** entry_test

**application**(<u>application_id</u>, *applicant_id*, *program_id*, *term_id*, snapshot_hs_score, snapshot_best_test, aggregate_score, submission_date, status)
- `applicant_id` → applicant(applicant_id) ON DELETE CASCADE
- `program_id` → program(program_id)
- `term_id` → term(term_id)
- UNIQUE (applicant_id, program_id, term_id) — one application per program per intake
- `status` ∈ {Pending, Selected, Waitlisted, Rejected, Enrolled, Declined}
- `snapshot_hs_score`, `snapshot_best_test`: point-in-time copies preserved at submission time

**offer**(<u>offer_id</u>, *application_id*, issue_date, expiry_date, status)
- `application_id` → application(application_id) ON DELETE CASCADE
- UNIQUE (application_id) — at most one offer per application
- `status` ∈ {Issued, Accepted, Declined, Expired}
- Maps the 1:0..1 relationship: application **yields** offer

---

### 2.5 Academic Pipeline

**student**(<u>student_id</u>, *program_id*, *applicant_id*, full_name, email, current_semester, enrollment_date)
- `program_id` → program(program_id)
- `applicant_id` → applicant(applicant_id) — UNIQUE (one student record per applicant)
- `email` UNIQUE
- `full_name` and `email` are denormalised copies from applicant (justified in design decisions doc)
- Maps the 1:0..1 relationship: applicant **becomes** student; program **registers** student

**enrollment**(<u>student_id</u>, <u>section_id</u>, attendance_percentage, grade)
- `student_id` → student(student_id) ON DELETE CASCADE
- `section_id` → section(section_id) ON DELETE CASCADE
- Composite PK = {student_id, section_id}
- `grade` ∈ {A, A-, B+, B, B-, C+, C, C-, D+, D, F} or NULL (in-progress)
- `attendance_percentage` ∈ [0, 100] or NULL (in-progress)
- Maps the M:N relationship: student **enrolls_in** section

---

## 3. Views (Derived Relations)

**student_transcript** — virtual relation:
> student_id, full_name, program_id, program_name, course_code, course_title, term_name, academic_year, grade, attendance_percentage

Defined by joining: student ⋈ program ⋈ enrollment ⋈ section ⋈ course ⋈ term

**classroom_utilization** — virtual relation:
> classroom_id, building, room_number, capacity, sections_hosted

Defined by: classroom LEFT JOIN section, grouped by classroom_id

---

## 4. Entity-Relationship to Relational Mapping Summary

| ER Construct | Relational Mapping |
|---|---|
| school | Direct table, no FK |
| faculty | Table + FK to school (1:N) |
| program | Table + FK to school (1:N) |
| course | Table + FK to school (1:N) |
| prerequisite | Composite-PK junction (M:N self-ref on course) |
| program_course | Composite-PK junction (M:N: program × course) with attributes |
| term | Direct table, no FK |
| classroom | Direct table, no FK |
| section | Table with 4 FKs (course, term, classroom, faculty) — resolves 4 relationships |
| applicant | Direct table |
| entry_test | Direct table |
| test_attempt | Composite-PK junction (M:N: applicant × entry_test) |
| application | Table with 3 FKs (applicant, program, term) + snapshot attributes |
| offer | Table + FK to application (1:0..1) |
| student | Table + FK to program and applicant (1:N and 1:0..1) |
| enrollment | Composite-PK junction (M:N: student × section) with attributes |

---

## 5. Integrity Constraints Summary

| Constraint | Location | Rule |
|---|---|---|
| PK uniqueness | All 16 tables | As defined above |
| NOT NULL | All PK and FK columns | Enforced by schema |
| UNIQUE cnic, email | applicant | One record per person |
| UNIQUE applicant_id | student | One student per applicant |
| CHECK no-self-loop | prerequisite | course_code ≠ prereq_course_code |
| UNIQUE (applicant, program, term) | application | One application per program per intake |
| UNIQUE application_id | offer | One offer per application |
| UNIQUE (term_name, academic_year) | term | No duplicate intakes |
| UNIQUE (course_code, term_id, label) | section | No duplicate sections |
| Capacity check | enrollment (trigger) | COUNT(enrollment) < classroom.capacity |
| Status promotion | student (trigger) | application → Enrolled; offer → Accepted |
| Score ranges | applicant | 0 ≤ high_school_score ≤ 1100; 0 ≤ best_test_score ≤ 200 |
| Grade enum | enrollment | Fixed grade set + NULL |
| ON DELETE CASCADE | Multiple FKs | Orphan cleanup |
