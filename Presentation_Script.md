# 10-Minute Presentation Script with Live Demo

**Project:** NUST DBS Agent — Natural Language SQL Assistant
**Audience:** DS course instructors and peers
**Format:** Slide narration + live demo

---

## Timing Overview

| Segment | Duration |
|---------|----------|
| 1. Hook + Problem | 1 min |
| 2. System Overview | 1.5 min |
| 3. Database Design | 2 min |
| 4. Live Demo | 3 min |
| 5. Technical Depth | 1.5 min |
| 6. Conclusion | 1 min |
| **Total** | **10 min** |

---

## Segment 1 — Hook and Problem Statement (1 min)

> *"Imagine you're an admissions officer at NUST. It's the first day of selections for Fall 2025. You need to know: how many applicants scored above 150 on their NET? Which programs are oversubscribed? Which applicants have been waitlisted?*
>
> *You could email IT and wait a day for a report. Or you could open this."*

**[Show screenshot or open the chat UI in browser]**

> *"This is the NUST DBS Agent. You type a question in plain English. It answers from live database data. No SQL. No waiting."*

**Key point to land:** The problem is not data availability — NUST has a rich database. The problem is **access friction**: only people who can write SQL can get answers, and that excludes most of the people who need them.

---

## Segment 2 — System Overview (1.5 min)

**[Show architecture diagram or draw on whiteboard]**

> *"Here's how it works at a high level."*

```
Browser (React chat UI)
    ↓ natural language question
FastAPI backend
    ↓ retrieves similar examples from FAISS vector store
    ↓ builds enhanced prompt with full schema context
LangGraph ReAct Agent
    ↓ reasons → generates SQL → validates → executes
    ↓ corrects errors automatically
MySQL database (16 tables)
    ↓ returns rows
Agent formulates plain English answer
    ↓
Browser displays answer + collapsible reasoning trace
```

> *"Three things make this work together: a local language model running on Ollama — no cloud, no API key, no student data leaving the server; LangGraph's ReAct loop for self-correcting SQL generation; and a carefully designed database schema that covers the full student lifecycle."*

**Emphasise:** Runs 100% locally. Privacy-preserving. Read-only — the model cannot modify any data.

---

## Segment 3 — Database Design (2 min)

**[Show ERD or schema summary]**

> *"The database is the core of the project. Let me walk you through the design in 90 seconds."*

**Two pipelines converging at student:**

> *"We have an admissions pipeline and an academic pipeline. They converge at the student table."*

**Admissions pipeline (left to right):**
- Applicant submits applications to programs for a specific term
- Sits the NUST Entry Test (up to 4 times per year, different test types)
- Application gets scored and given a status: Selected, Waitlisted, Rejected
- Selected applicants receive an offer with an expiry date
- Accepting the offer creates a student record, which triggers automatic status updates

**Academic pipeline (top to bottom):**
- School → programs and courses (M:N via program_course junction)
- Courses have prerequisites (self-referential M:N)
- Each term, sections are scheduled with a faculty member in a classroom
- Students enroll in sections; grade and attendance are tracked per enrollment

**Highlight two interesting design choices:**

1. *"Snapshot columns on application: we capture the high school score and test score at submission time. If the applicant later retakes the NET, it doesn't retroactively change their submitted application. This is standard practice for audit trails."*

2. *"Two database triggers: one enforces classroom capacity at enrollment time — the database itself rejects over-enrollments. The second trigger automatically promotes an application to Enrolled when a student record is created, keeping the admissions and academic pipelines in sync atomically."*

> *"All 16 relations satisfy BCNF. The two acknowledged denormalisations — a cached best_test_score on applicant, and name/email copied to the student table — are deliberate trade-offs for query performance, not normal form violations."*

---

## Segment 4 — Live Demo (3 min)

**Pre-demo checklist (do this before the presentation starts):**
- [ ] MySQL server running, nust_university database loaded
- [ ] Ollama running with llama3.1 model pulled (`ollama run llama3.1`)
- [ ] Backend started: `cd test-sql-rag && python api.py` (wait for "Application startup complete")
- [ ] Frontend started: `cd frontend && npm run dev` (http://localhost:5173)
- [ ] Browser tab open at http://localhost:5173
- [ ] Browser console closed (less distraction)

---

### Demo Question 1 — Quick win (~30 seconds)

**Type:** *"Which program received the most applications?"*

**Expected answer:** Computer Science received the most applications, with 6 in total. Software Engineering is next with 3.

**While it loads, narrate:**
> *"Notice the UI shows a typing indicator. The agent is reasoning in the background — it's deciding which tables to look at, generating SQL, validating it, and executing it."*

**After answer appears:**
> *"Click 'Show reasoning' to expand the steps."*

**[Click the reasoning toggle]**
> *"You can see exactly what SQL it ran, what the raw results were, and how the agent composed its answer. Full transparency."*

---

### Demo Question 2 — Aggregation and Filtering (~45 seconds)

**Type:** *"List the top 5 applicants by their best NET score."*

**Expected answer:** A bulleted list with applicant names and scores.

**Narrate:**
> *"This crosses two tables: it needs the applicant's name and their best test score. The agent knows the schema and generates the right join automatically."*

---

### Demo Question 3 — Multi-table join (~1 minute)

**Type:** *"Show me the full transcript for student S001."*

**Expected answer:** A list of courses, terms, grades, and attendance for that student.

**Narrate:**
> *"This is the hardest query in the system — it joins seven tables: student, program, enrollment, section, course, and term. The agent does this correctly because the system prompt documents the exact join paths."*

---

### Demo Question 4 — Scope enforcement (~30 seconds)

**Type:** *"How many students does MIT enroll each year?"*

**Expected answer:** The refusal message: "I am an assistant for the NUST University Database. I cannot answer questions unrelated to NUST admissions or academic data."

**Narrate:**
> *"The agent checks scope before calling any tool. Questions about other universities, countries, or topics outside NUST are refused immediately — no database call is made, no tokens wasted."*

---

### Demo Question 5 — Bonus if time allows (~15 seconds)

**Type:** *"How many students are currently in progress in Database Systems?"*

**Expected answer:** A count of students with grade IS NULL for that course.

---

## Segment 5 — Technical Depth (1.5 min)

> *"Let me highlight three technical choices that separate this from a naive 'just ask the LLM to write SQL' approach."*

**1. Semantic few-shot injection:**
> *"We have 22 example Q&A pairs stored in a FAISS vector index. When you submit a question, we find the most similar example using embedding similarity. If the match is close enough, we inject that example's SQL as guidance into the prompt. This dramatically improves accuracy on known query patterns without bloating the prompt for every question."*

**2. ReAct self-correction loop:**
> *"If the generated SQL fails — wrong column name, missing join, syntax error — the LangGraph agent sees the error from the query checker tool and tries again. In testing, about 15% of first-attempt queries need one correction. The loop handles this transparently."*

**3. Schema injection:**
> *"The full schema — CREATE TABLE statements plus sample rows — is injected into the system prompt at startup. The agent knows every table, every column, every foreign key relationship. This is why it can navigate a 16-table schema correctly without guessing."*

---

## Segment 6 — Conclusion (1 min)

> *"To summarise: we built a system that turns natural English into correct MySQL queries over a 16-table university database, runs entirely on local infrastructure, and is accessible to anyone with a browser.*

> *The database itself required careful design — 16 normalised relations, 2 views, 2 triggers, 22 indexes — to make the data semantically accessible to the agent.*

> *The agent layer adds schema-aware prompt engineering, semantic few-shot retrieval, and self-correcting SQL generation.*

> *Together, they solve the access friction problem: administrative staff get the data they need, without needing to know SQL."*

**[Take questions]**

---

## Anticipated Q&A

**Q: Why not just use GPT-4?**
A: Privacy. Student CNICs, grades, and admissions outcomes are PII. Sending them to a cloud API requires a data processing agreement. Ollama runs locally; nothing leaves the server.

**Q: How accurate is it?**
A: On the 22 few-shot examples, accuracy is very high (the examples are in the training distribution). For novel queries, accuracy depends on query complexity. Simple aggregations and filters: very reliable. Complex multi-level subqueries: sometimes need rephrasing. The reasoning trace lets the user verify the SQL that was run.

**Q: Can someone trick it into modifying data?**
A: Two layers of protection: the system prompt instructs it to only generate SELECT statements, and the MySQL user account has only SELECT privileges. Even if the LLM generated a DELETE, the database would reject it.

**Q: Why 22 few-shot examples? Why not more?**
A: 22 covers the main query patterns for this domain. Adding more would increase the FAISS index size and embedding time but provide diminishing returns. The threshold-based injection means only truly relevant examples are used anyway.

**Q: What happens if Ollama is slow?**
A: The backend streams the agent's response incrementally (LangGraph stream mode). The frontend shows a typing indicator while waiting. The agent typically responds in 5–15 seconds on a local GPU; longer on CPU-only machines.
