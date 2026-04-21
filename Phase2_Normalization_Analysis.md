# Phase 2 — Normalization Analysis

---

## 1. Overview

This document analyses the functional dependencies in each relation of the NUST university database and proves that every relation is in **Third Normal Form (3NF)**, with notes on where **Boyce-Codd Normal Form (BCNF)** is achieved and where a deliberate, justified deviation exists.

Notation used:
- `PK` = primary key attribute(s)
- `A → B` = A functionally determines B
- `A ↛ B` = A does not functionally determine B (used to rule out anomalies)

---

## 2. Background: Normalization Definitions

**1NF:** Every attribute is atomic; no repeating groups; each row is uniquely identified.

**2NF:** In 1NF, and every non-key attribute is **fully functionally dependent** on the entire primary key (eliminates partial dependencies; relevant only when PK is composite).

**3NF:** In 2NF, and no non-key attribute is **transitively dependent** on the primary key through another non-key attribute.

**BCNF:** In 3NF, and for every non-trivial FD X → Y, X is a superkey (stronger than 3NF; eliminates certain anomalies that 3NF allows when there are overlapping candidate keys).

---

## 3. Relation-by-Relation Analysis

---

### 3.1 school

**Schema:** school(<u>school_id</u>, school_name, abbreviation, established_year)

**Candidate keys:** {school_id}, {school_name}, {abbreviation} — all three are unique.

**Functional Dependencies:**
- school_id → school_name, abbreviation, established_year ✓
- school_name → school_id, abbreviation, established_year ✓
- abbreviation → school_id, school_name, established_year ✓

**1NF:** All attributes atomic. ✓
**2NF:** PK is single-attribute; no partial dependencies possible. ✓
**3NF:** All non-key attributes depend directly on each candidate key; no transitive chains. ✓
**BCNF:** Every FD's determinant is a candidate key. **BCNF achieved.** ✓

---

### 3.2 faculty

**Schema:** faculty(<u>faculty_id</u>, school_id, full_name, email, designation)

**Candidate keys:** {faculty_id}, {email}

**Functional Dependencies:**
- faculty_id → school_id, full_name, email, designation ✓
- email → faculty_id, school_id, full_name, designation ✓

No transitive dependencies: school_id is a FK reference, not a determinant of other attributes within this relation.

**3NF:** ✓ — `school_id` is determined by `faculty_id` directly, not transitively through another non-key attribute.
**BCNF:** Every FD's determinant ({faculty_id} or {email}) is a candidate key. **BCNF achieved.** ✓

---

### 3.3 program

**Schema:** program(<u>program_id</u>, school_id, program_name, degree_type, total_semesters, total_credits, total_seats)

**Candidate keys:** {program_id}, {program_name} (program names are unique in practice, though not enforced with a UNIQUE constraint — treated as a candidate key for analysis).

**Functional Dependencies:**
- program_id → school_id, program_name, degree_type, total_semesters, total_credits, total_seats ✓

Is there a transitive dependency? Does `degree_type → total_semesters`? No — BBA and BSCS both have 8 semesters but different credit counts; the mapping is not functional. Each program's parameters are independently set.

**3NF:** ✓ **BCNF:** ✓

---

### 3.4 course

**Schema:** course(<u>course_code</u>, school_id, course_title, course_type, credit_hours, contact_hours)

**Candidate keys:** {course_code}

**Functional Dependencies:**
- course_code → school_id, course_title, course_type, credit_hours, contact_hours ✓

Is `course_type → credit_hours`? No — Lab courses can have 1 or 3 credit hours depending on the course; not a functional dependency.

**3NF:** ✓ **BCNF:** ✓

---

### 3.5 prerequisite

**Schema:** prerequisite(<u>course_code</u>, <u>prereq_course_code</u>)

**Candidate keys:** {course_code, prereq_course_code} (the entire tuple is the key)

**Functional Dependencies:**
- No non-key attributes exist. The relation is a pure junction (all-key relation).

An all-key relation trivially satisfies all normal forms.

**3NF:** ✓ **BCNF:** ✓

---

### 3.6 program_course

**Schema:** program_course(<u>program_id</u>, <u>course_code</u>, recommended_semester, is_core)

**Candidate keys:** {program_id, course_code}

**Functional Dependencies:**
- {program_id, course_code} → recommended_semester, is_core ✓
- program_id ↛ recommended_semester (same course has different recommended semesters in different programs)
- course_code ↛ recommended_semester (partial dependency ruled out)
- recommended_semester ↛ is_core (no transitive dependency — a course can be core in semester 3 and elective in semester 4 in different programs)

**2NF:** No partial dependencies. ✓
**3NF:** No transitive dependencies. ✓
**BCNF:** The only FD has the PK as its determinant. **BCNF achieved.** ✓

---

### 3.7 term

**Schema:** term(<u>term_id</u>, term_name, academic_year, start_date, end_date)

**Candidate keys:** {term_id}, {term_name, academic_year}

**Functional Dependencies:**
- term_id → term_name, academic_year, start_date, end_date ✓
- {term_name, academic_year} → term_id, start_date, end_date ✓

Is `academic_year → start_date`? No — the exact start date varies per term; academic year alone does not determine start_date.

**3NF:** ✓ **BCNF:** Every FD's determinant is a candidate key. **BCNF achieved.** ✓

---

### 3.8 classroom

**Schema:** classroom(<u>classroom_id</u>, building, room_number, capacity)

**Candidate keys:** {classroom_id}, {building, room_number}

**Functional Dependencies:**
- classroom_id → building, room_number, capacity ✓
- {building, room_number} → classroom_id, capacity ✓

Is `building → capacity`? No — different rooms in the same building have different capacities.

**3NF:** ✓ **BCNF:** Both FDs have candidate keys as determinants. **BCNF achieved.** ✓

---

### 3.9 applicant

**Schema:** applicant(<u>applicant_id</u>, full_name, cnic, email, high_school_board, high_school_score, best_test_score)

**Candidate keys:** {applicant_id}, {cnic}, {email}

**Functional Dependencies:**
- applicant_id → full_name, cnic, email, high_school_board, high_school_score, best_test_score ✓
- cnic → applicant_id, full_name, email, high_school_board, high_school_score, best_test_score ✓
- email → (same set) ✓

**Note on best_test_score:** This is a denormalised cache of MAX(test_attempt.score). In strict BCNF, this creates an anomaly: if test_attempt rows change, best_test_score must be manually updated. This is a **deliberate design decision** (see Phase 2 Design Decisions doc). The relation itself still satisfies 3NF/BCNF in isolation — the redundancy lives across relations, not within this one.

**3NF:** ✓ **BCNF:** ✓ (within this relation)

---

### 3.10 entry_test

**Schema:** entry_test(<u>test_id</u>, academic_year, net_number, test_type, test_date, total_marks)

**Candidate keys:** {test_id}, {academic_year, net_number, test_type}

**Functional Dependencies:**
- test_id → academic_year, net_number, test_type, test_date, total_marks ✓
- {academic_year, net_number, test_type} → test_id, test_date, total_marks ✓

Is `academic_year → total_marks`? No — total_marks could in principle change (though currently always 200). The dependency is on the full candidate key.

**3NF:** ✓ **BCNF:** Both FDs have candidate keys as determinants. **BCNF achieved.** ✓

---

### 3.11 test_attempt

**Schema:** test_attempt(<u>applicant_id</u>, <u>test_id</u>, score)

**Candidate keys:** {applicant_id, test_id}

**Functional Dependencies:**
- {applicant_id, test_id} → score ✓
- applicant_id ↛ score (an applicant's score differs per sitting)
- test_id ↛ score (different applicants score differently on the same test)

**2NF:** No partial dependencies. ✓
**3NF:** score is not transitively dependent on anything. ✓
**BCNF:** The only FD has the PK as its determinant. **BCNF achieved.** ✓

---

### 3.12 application

**Schema:** application(<u>application_id</u>, applicant_id, program_id, term_id, snapshot_hs_score, snapshot_best_test, aggregate_score, submission_date, status)

**Candidate keys:** {application_id}, {applicant_id, program_id, term_id}

**Functional Dependencies:**
- application_id → applicant_id, program_id, term_id, snapshot_hs_score, snapshot_best_test, aggregate_score, submission_date, status ✓
- {applicant_id, program_id, term_id} → application_id, snapshot_hs_score, snapshot_best_test, aggregate_score, submission_date, status ✓

Is there a transitive dependency? Does `status → submission_date` or vice versa? No — status and submission_date are independent attributes.

Are `snapshot_hs_score` and `snapshot_best_test` redundant with `applicant.high_school_score` and `applicant.best_test_score`? They represent a **point-in-time snapshot** at submission, not the current value on the applicant record. They are semantically distinct attributes — no functional dependency violation. This is standard practice for audit trails.

**2NF:** The non-key attributes (snapshot_hs_score, etc.) depend on the full composite candidate key, not just part of it. No partial dependency on {applicant_id} alone or {program_id} alone. ✓
**3NF:** No transitive dependencies through non-key attributes. ✓
**BCNF:** Both candidate keys are superkeys. **BCNF achieved.** ✓

---

### 3.13 offer

**Schema:** offer(<u>offer_id</u>, application_id, issue_date, expiry_date, status)

**Candidate keys:** {offer_id}, {application_id} (UNIQUE constraint)

**Functional Dependencies:**
- offer_id → application_id, issue_date, expiry_date, status ✓
- application_id → offer_id, issue_date, expiry_date, status ✓

**3NF:** ✓ **BCNF:** Both FDs have candidate keys as determinants. **BCNF achieved.** ✓

---

### 3.14 student ← Known Deviation from BCNF

**Schema:** student(<u>student_id</u>, program_id, applicant_id, full_name, email, current_semester, enrollment_date)

**Candidate keys:** {student_id}, {applicant_id}, {email}

**Functional Dependencies:**
- student_id → program_id, applicant_id, full_name, email, current_semester, enrollment_date ✓
- applicant_id → student_id, program_id, full_name, email, current_semester, enrollment_date ✓
- email → student_id, program_id, applicant_id, full_name, current_semester, enrollment_date ✓

**Potential transitive dependency — analysed:**

Does `applicant_id → full_name` create a transitive dependency? In a strict BCNF sense, `full_name` is already determined by `applicant_id` via the `applicant` table — it is derivable via JOIN. Storing it here introduces the possibility of update anomaly if the applicant's name changes.

However, `applicant_id` is itself a candidate key of `student`. The FD `applicant_id → full_name` has a superkey as its determinant, which satisfies BCNF. The concern is a cross-relation redundancy (between `student.full_name` and `applicant.full_name`), which is a denormalization choice, not a normalization violation within this relation.

Similarly, `student.program_id` is a direct FK here, not derived transitively — there is no intermediate non-key attribute in the chain.

**Conclusion within this relation:**
- Every FD's determinant ({student_id}, {applicant_id}, {email}) is a candidate key.
- **BCNF is satisfied within this relation.**

**Cross-relation redundancy (acknowledged):**
- `student.full_name` duplicates `applicant.full_name`
- `student.email` duplicates `applicant.email`
- This is a deliberate denormalization for query ergonomics, documented in the design decisions document. The duplication is bounded (one row per student), and the application layer maintains consistency at insert time.

---

### 3.15 section

**Schema:** section(<u>section_id</u>, course_code, term_id, classroom_id, faculty_id, section_label)

**Candidate keys:** {section_id}, {course_code, term_id, section_label}

**Functional Dependencies:**
- section_id → course_code, term_id, classroom_id, faculty_id, section_label ✓
- {course_code, term_id, section_label} → section_id, classroom_id, faculty_id ✓

Is there a transitive dependency? Does `classroom_id → faculty_id`? No — a classroom can host multiple faculty; faculty assignment is independent of room assignment.

Does `course_code → faculty_id`? No — the same course can be taught by different faculty in different sections.

**3NF:** ✓ **BCNF:** Both FD determinants are candidate keys. **BCNF achieved.** ✓

---

### 3.16 enrollment

**Schema:** enrollment(<u>student_id</u>, <u>section_id</u>, attendance_percentage, grade)

**Candidate keys:** {student_id, section_id}

**Functional Dependencies:**
- {student_id, section_id} → attendance_percentage, grade ✓
- student_id ↛ grade (a student's grade differs per section)
- section_id ↛ grade (different students have different grades in the same section)

**2NF:** Both non-key attributes are fully dependent on the composite PK. ✓
**3NF:** No transitive dependencies — grade does not determine attendance or vice versa. ✓
**BCNF:** The only FD has the composite PK as its determinant. **BCNF achieved.** ✓

---

## 4. Summary Table

| Relation | 1NF | 2NF | 3NF | BCNF | Notes |
|----------|-----|-----|-----|------|-------|
| school | ✓ | ✓ | ✓ | ✓ | 3 candidate keys |
| faculty | ✓ | ✓ | ✓ | ✓ | |
| program | ✓ | ✓ | ✓ | ✓ | |
| course | ✓ | ✓ | ✓ | ✓ | |
| prerequisite | ✓ | ✓ | ✓ | ✓ | All-key relation |
| program_course | ✓ | ✓ | ✓ | ✓ | |
| term | ✓ | ✓ | ✓ | ✓ | Composite candidate key |
| classroom | ✓ | ✓ | ✓ | ✓ | |
| applicant | ✓ | ✓ | ✓ | ✓ | best_test_score is cross-relation redundancy, not intra-relation violation |
| entry_test | ✓ | ✓ | ✓ | ✓ | |
| test_attempt | ✓ | ✓ | ✓ | ✓ | All-key + one attribute |
| application | ✓ | ✓ | ✓ | ✓ | Snapshot cols are semantically distinct |
| offer | ✓ | ✓ | ✓ | ✓ | |
| student | ✓ | ✓ | ✓ | ✓ | Cross-relation redundancy acknowledged; BCNF holds within relation |
| section | ✓ | ✓ | ✓ | ✓ | |
| enrollment | ✓ | ✓ | ✓ | ✓ | |

**All 16 relations satisfy 3NF. All 16 relations also satisfy BCNF.**

The two acknowledged redundancies (`applicant.best_test_score` and `student.full_name / email`) are cross-relation denormalisations introduced for performance and query ergonomics, not intra-relation normal form violations.

---

## 5. Cross-Relation Redundancies (Acknowledged Denormalisations)

### 5.1 applicant.best_test_score

**Nature:** This column caches `MAX(score)` from `test_attempt` for this applicant.

**Dependency:** applicant_id → best_test_score is valid as an intra-relation FD (applicant_id is the PK). The cross-relation concern is that `best_test_score` should equal the maximum of all test_attempt.score rows for the same applicant_id.

**Anomaly risk:** If a new test_attempt row is added with a higher score, `best_test_score` must be updated manually. If not, aggregate_score calculations on application records will use stale data.

**Justification:** Avoids a correlated subquery on every application aggregate calculation. Treated as a write-time maintained column.

### 5.2 student.full_name and student.email

**Nature:** These duplicate `applicant.full_name` and `applicant.email` for the same person.

**Dependency:** applicant_id → full_name (in both `applicant` and `student`), creating cross-relation redundancy.

**Anomaly risk:** If `applicant.full_name` is corrected (e.g., typo fix), `student.full_name` is not automatically updated.

**Justification:** The `student` table is the primary access point for academic queries. Carrying name and email directly on `student` eliminates a JOIN to `applicant` in the most common query paths (transcript, enrollment roster, grade reports).
