# Phase 1 — Problem Statement, Domain Description, and Functional Requirements

---

## 1. Problem Statement

The National University of Sciences and Technology (NUST), Islamabad, manages a large and operationally critical database spanning undergraduate admissions, academic scheduling, faculty assignments, and student progress. Staff across the Registrar's Office, Admissions Directorate, and individual schools routinely need answers from this data: which applicants scored above a threshold, how many seats remain in a program, what the grade distribution for a course looks like, which classrooms are over-utilised.

Currently, obtaining these answers requires either writing SQL queries directly against the MySQL database—a skill most administrative staff do not have—or waiting for IT to pull reports on request. Both paths are slow, error-prone, and create a bottleneck that imposes real cost on institutional decision-making.

This project builds **NUST DBS Agent**: a natural-language SQL assistant that lets non-technical staff query the university database in plain English. A staff member types "Which applicants were rejected despite scoring above 140 on their NET?" and receives a concise, plain-English answer in seconds, with no SQL knowledge required. The system runs entirely on local infrastructure using an open-source LLM (Llama 3.1 via Ollama), so no sensitive student or admissions data leaves the university network.

---

## 2. Domain Description

### 2.1 University Structure

NUST is organised into ten constituent schools (SEECS, SMME, NBS, SADA, NICE, S3H, ASAB, SCME, CAMP, MCS). Each school:

- Employs a set of **faculty** members with ranks from Lecturer to Professor.
- Offers one or more **undergraduate programs** (BS, BE, BBA, BArch) with a defined credit and semester count.
- Owns a set of **courses** that may be shared across programs through a curriculum mapping.

### 2.2 Admissions Pipeline

Admission to NUST is competitive and follows a structured process:

1. **Application:** A prospective student (**applicant**) submits an application to a specific program for a specific intake **term** (Fall/Spring/Summer of a given year).
2. **Entry Test:** NUST administers the **NUST Entry Test (NET)**, held up to four times per year in multiple sittings, covering Engineering, CS, Business, Architecture, Biosciences, and Chemical streams. Each applicant may attempt multiple sittings; the best score is cached on the applicant record.
3. **Selection:** An **aggregate score** is computed from the applicant's high school result and best NET score. The application moves through statuses: Pending → Selected / Waitlisted / Rejected.
4. **Offer:** A selected applicant receives a formal **admission offer** with an expiry date. The offer status tracks whether it was Accepted, Declined, or Expired.
5. **Enrollment:** An applicant who accepts their offer becomes a **student**, triggering an automatic status promotion in both the application (→ Enrolled) and offer (→ Accepted) records.

Snapshot columns on the application record (`snapshot_hs_score`, `snapshot_best_test`) preserve the scores that existed at submission time, maintaining an audit trail even if the applicant later attempts additional tests.

### 2.3 Academic Pipeline

Once enrolled, the academic lifecycle proceeds as follows:

1. **Curriculum:** Each program has a curriculum defined through a many-to-many **program_course** junction, specifying which courses are core vs. elective and their recommended semester. Courses may have **prerequisites** (a directed acyclic graph of dependencies—e.g., Data Structures requires Programming Fundamentals).
2. **Sections:** Each term, the university schedules one or more **sections** of a course, assigning a faculty member and a **classroom**. Classroom capacity is the hard upper bound on section size.
3. **Enrollment:** Students register for sections. Each enrollment record tracks **attendance** and **grade** (NULL while the course is in progress; set upon completion).
4. **Transcript:** The full academic record—program, all courses taken, terms, grades, attendance—is exposed through a `student_transcript` view.

### 2.4 System Scope

The database covers:

| In Scope | Out of Scope |
|----------|-------------|
| Admissions (applicant → offer) | Financial data (fee challans, scholarships) |
| Academic scheduling (sections, classrooms) | Research publications |
| Student academic records (grades, attendance) | Hostel and facilities beyond classrooms |
| Faculty assignments | HR payroll |
| Course curriculum and prerequisites | External exam results beyond NET |

---

## 3. Stakeholders

| Stakeholder | Typical Query |
|-------------|--------------|
| Admissions Officer | "How many applicants are waitlisted for BSCS this intake?" |
| Registrar Staff | "What is the grade distribution for CS212 in Fall 2025?" |
| Academic Advisor | "Which core courses has student S003 not yet completed?" |
| School Management | "How many faculty does SEECS have, by designation?" |
| Facility Manager | "Which classrooms are hosting more than two sections this term?" |

---

## 4. Technical Context

The system is a **Retrieval-Augmented Generation (RAG) agent** with the following stack:

| Layer | Technology |
|-------|-----------|
| Language Model | Llama 3.1 7B via Ollama (local, no cloud calls) |
| Agent Framework | LangGraph ReAct + LangChain SQL Toolkit |
| Vector Store | FAISS with nomic-embed-text embeddings |
| Backend API | FastAPI (Python) |
| Database | MySQL 8.0, 16 tables, InnoDB engine |
| Frontend | React 19 + Vite + Tailwind CSS (dark-themed chat UI) |

The agent follows a **ReAct loop**: it reasons about which tables to inspect, generates SQL, validates it with a query-checker tool, executes it, and then formulates a plain-English answer. Semantic few-shot examples (22 Q&A pairs stored in FAISS) are injected into the prompt when a close match is found, improving SQL accuracy without expanding the prompt for every query.

All queries are strictly `SELECT`-only; no data modification is possible through the chat interface.

---

## 5. Functional Requirements

### FR-01 Natural Language Query Interface
The system shall accept questions in plain English via a web chat interface and return plain-English answers grounded in live database results.

### FR-02 SQL Generation
The agent shall automatically generate valid MySQL `SELECT` queries from the user's question, using the full schema (16 tables, 2 views) as context.

### FR-03 Query Self-Correction
If a generated query fails (syntax error, unknown column, etc.), the agent shall retry with a corrected query before returning an error to the user.

### FR-04 Semantic Few-Shot Injection
The system shall maintain a vector store of example Q&A pairs. When a user query is semantically similar to a stored example (cosine/L2 distance below threshold 0.35), the matching SQL shall be injected as guidance into the agent prompt.

### FR-05 Read-Only Enforcement
The system shall only execute `SELECT` statements. Any query containing `INSERT`, `UPDATE`, `DELETE`, `DROP`, `CREATE`, `ALTER`, or equivalent DDL/DML shall be refused.

### FR-06 Scope Enforcement
The agent shall refuse questions unrelated to NUST admissions or academic data, responding with a fixed refusal message instead of calling any database tool.

### FR-07 Reasoning Transparency
The API response shall include the full reasoning trace (LLM thoughts, tool calls, tool results) as a structured `steps` array, allowing the frontend to display a collapsible reasoning panel.

### FR-08 Schema Introspection Endpoint
The system shall expose a `GET /api/schema` endpoint that returns the full table-column mapping, enabling frontend schema browsing.

### FR-09 Admissions Data Management (Database)
The database shall store and maintain: applicant profiles, entry test sessions, test attempts, applications with status lifecycle, and admission offers with status lifecycle.

### FR-10 Academic Data Management (Database)
The database shall store and maintain: programs, courses, prerequisites, curriculum mappings, terms, classrooms, faculty assignments, sections, student records, and enrollments with grades and attendance.

### FR-11 Capacity Enforcement (Trigger)
The database shall enforce classroom capacity at enrollment time via a `BEFORE INSERT` trigger that rejects over-capacity enrollments.

### FR-12 Automatic Status Promotion (Trigger)
When a new student record is inserted, the database shall automatically promote the corresponding application status to `Enrolled` and the corresponding offer status to `Accepted` via an `AFTER INSERT` trigger.

### FR-13 Transcript View
The system shall expose a `student_transcript` view joining student, enrollment, section, course, program, and term data for easy full-record retrieval.

### FR-14 Classroom Utilisation View
The system shall expose a `classroom_utilization` view aggregating section counts per room, including rooms with zero sections.

### FR-15 Default Result Limiting
Unless the user explicitly requests more, query results shall be limited to 5 rows to keep answers concise.
