# Phase 2 — Design Decisions and Justifications

---

## Overview

This document records the non-obvious design choices made during the schema and application design of the NUST DBS Agent, with a brief justification for each. The goal is to explain *why* a particular approach was chosen over common alternatives, so that future maintainers can evaluate whether the original rationale still holds.

---

## 1. Human-Readable VARCHAR Primary Keys

**Decision:** All primary keys are VARCHAR codes (e.g., `SEECS`, `BSCS`, `FA25`, `S001`) rather than auto-increment integers or UUIDs.

**Justification:**
- Administrative staff and developers can read query results and logs without cross-referencing a lookup table.
- The codes are already in use institutionally (NUST uses SEECS, BSCS etc. in official communications), so there is no translation overhead.
- The natural language agent produces much more readable SQL when filtering by `program_id = 'BSCS'` rather than `program_id = 14`.
- Foreign key joins remain self-documenting in query output.

**Trade-off:** VARCHAR PKs consume slightly more storage and have slower equality comparisons than integers on very large tables. At the scale of a university (tens of thousands of rows, not billions), this is negligible.

---

## 2. Student Carries Direct FKs to Both program and applicant

**Decision:** The `student` table has direct foreign keys to both `program` and `applicant`, rather than linking to program only via `application`.

**Justification:**
- The most common academic queries (transcript, enrollment, grade reports) need `student → program` and `student → applicant`. Forcing them through `application` adds an unnecessary join and conflates the admissions lifecycle with the academic record.
- An applicant may have multiple applications (different programs, different terms). At enrollment time, exactly one application is authoritative. Encoding that fact directly on `student` makes it unambiguous which program the student is in.
- The `auto_update_application_status` trigger maintains consistency: when a student record is created, the correct application is marked `Enrolled`.

**Acknowledged trade-off:** `student.full_name` and `student.email` duplicate `applicant.full_name` and `applicant.email`. This is a bounded, write-time redundancy. At insert time the application layer copies these fields; a name correction on the applicant record would need to propagate manually to the student record.

---

## 3. Courses Owned by Schools, Not Programs

**Decision:** `course.school_id` points to the owning school, and the M:N relationship between programs and courses is handled by the `program_course` junction table.

**Justification:**
- A course like CS118 (Programming Fundamentals) is legitimately part of BSCS, BESE, and BECE curricula. Attaching it to one program would require duplication or a different design.
- Ownership at the school level correctly models institutional reality: SEECS creates and maintains CS courses; NBS maintains MGT courses.
- The `program_course` junction allows each program to specify the recommended semester and whether the course is core or elective — attributes that belong to the relationship, not to the course or the program alone.

---

## 4. Offer as a Separate Entity from Application

**Decision:** Admission offers are stored in a dedicated `offer` table rather than as columns on `application`.

**Justification:**
- Offer has its own lifecycle (Issued → Accepted / Declined / Expired) that is independent of the application lifecycle (Pending → Selected → Enrolled).
- Separating them allows the system to model the case where an offer is issued, expires, and the application is re-evaluated for a later intake — without overwriting the original application record.
- The 1:0..1 relationship (one application may yield at most one offer) is cleanly enforced by a UNIQUE constraint on `offer.application_id`.

---

## 5. Snapshot Columns on application

**Decision:** `application.snapshot_hs_score` and `application.snapshot_best_test` duplicate the applicant's scores as they were at submission time.

**Justification:**
- NUST admissions policy computes aggregate scores from the scores valid at submission. If an applicant later sits another NET and improves their score, it should not retroactively change the aggregate for a previously submitted application.
- The snapshot columns provide an immutable audit trail. This is a standard pattern in admissions and financial systems where historical accuracy is legally required.
- These are semantically distinct from `applicant.best_test_score` (current best) and `test_attempt.score` (per-sitting result). They are not redundant in the normalization sense — they represent different facts.

---

## 6. applicant.best_test_score as a Maintained Cache

**Decision:** `applicant.best_test_score` caches the maximum score across all test attempts rather than computing it on demand.

**Justification:**
- Aggregate calculations for application ranking repeatedly need the best score. Computing `MAX(ta.score) WHERE ta.applicant_id = ?` as a subquery on every `SELECT` from `application` adds cost at read time.
- The cache is updated at write time (on each test_attempt insert), which is far less frequent than reads.

**Trade-off:** If a test_attempt row is deleted or corrected, the cache must be manually refreshed. This is acceptable because test records are immutable in practice — NUST does not retroactively change test scores.

---

## 7. Capacity Enforcement via Trigger (Not CHECK Constraint)

**Decision:** Classroom capacity is enforced by a `BEFORE INSERT` trigger on `enrollment`, not by a CHECK constraint.

**Justification:**
- MySQL CHECK constraints operate on single-row values. The capacity rule requires an aggregate: `COUNT(enrollment WHERE section_id = ?) < classroom.capacity`. Aggregate-based constraints cannot be expressed as CHECK constraints in MySQL.
- A trigger can query the current enrollment count and compare it to the classroom capacity at insert time, providing the necessary cross-row validation.
- The trigger raises a clear, user-readable error: "Enrollment failed: classroom capacity reached."

---

## 8. Auto Status Promotion via Trigger

**Decision:** The `auto_update_application_status` trigger automatically promotes application status to `Enrolled` and offer status to `Accepted` when a student record is inserted.

**Justification:**
- These three updates (insert student, update application, update offer) must always happen atomically. Relying on the application layer to execute all three creates a risk of partial updates if the application crashes between operations.
- Encoding the logic in a database trigger ensures the invariant is maintained regardless of which client inserts the student record.
- The trigger is narrowly scoped: it only fires on student INSERT and only modifies rows with matching (applicant_id, program_id).

---

## 9. grade NULL for In-Progress Enrollments

**Decision:** `enrollment.grade` is NULL while the course is ongoing, not a placeholder value like `'IP'` or `'0'`.

**Justification:**
- NULL correctly conveys "not yet determined" — the grade does not exist yet.
- Using a placeholder string or 0 would corrupt aggregate calculations (GPA, grade distribution queries) unless every query explicitly filtered it out.
- `WHERE grade IS NULL` is the natural SQL idiom for filtering in-progress enrollments, and it works correctly with all standard aggregate functions.

---

## 10. Local LLM (Ollama) for Privacy

**Decision:** The system uses Llama 3.1 via Ollama running locally, rather than a cloud-based LLM API (OpenAI GPT-4, Claude, etc.).

**Justification:**
- University admissions and academic records contain personally identifiable information (PII) — applicant CNICs, names, scores, student grades. Sending this data to a third-party cloud API would require a data processing agreement and raises PDPA (Pakistan's data protection framework) compliance concerns.
- A local LLM keeps all data within the university's network perimeter.
- Ollama is free and open-source; there are no per-query costs, which matters for a system potentially handling thousands of queries per day.

**Trade-off:** Llama 3.1 7B is less capable than GPT-4 class models. SQL accuracy is compensated by the schema injection, few-shot examples, and the ReAct self-correction loop.

---

## 11. FAISS Few-Shot Vector Store with Similarity Threshold

**Decision:** 22 example Q&A pairs are stored in a FAISS vector index. Examples are only injected into the prompt when the best L2 similarity score is below a threshold of 0.35.

**Justification:**
- Injecting examples unconditionally would add ~300 tokens to every prompt with no benefit for novel queries.
- A similarity threshold ensures that only genuinely relevant examples are included, reducing noise and token cost while improving SQL accuracy on queries that closely match a known pattern.
- 0.35 was tuned empirically: too low (e.g., 0.20) causes too few injections; too high (e.g., 0.60) injects irrelevant examples.

---

## 12. Strict Read-Only Enforcement at the Agent Level

**Decision:** The system prompt and tool configuration permit only SELECT queries. The prompt explicitly instructs the agent to never use INSERT, UPDATE, DELETE, DROP, CREATE, or ALTER.

**Justification:**
- The chat interface is intended for read-only analytics queries by non-technical staff. Write access through a natural language interface is a significant security risk — a misinterpreted instruction could corrupt or delete data.
- Defense in depth: the MySQL user account used by the application has only SELECT privileges at the database level, providing a second layer of enforcement independent of the LLM's compliance with the system prompt.

---

## 13. Index Strategy

**Decision:** 22 explicit indexes were created beyond the implicit PK indexes.

**Justification:**
- The most frequent query patterns join through FK paths: `enrollment → section → course`, `application → program → school`, `student → program`. Indexes on FK columns (`idx_enrollment_section`, `idx_section_course`, etc.) convert these full-table scans into index seeks.
- Selective filter columns (`application.status`, `offer.status`) are indexed to support common WHERE clauses like `WHERE status = 'Selected'`.
- Index creation is selective: columns with low cardinality (e.g., boolean flags) or rarely filtered are not indexed to avoid write overhead with no read benefit.
