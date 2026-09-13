# Repository instructions

- Treat the SAP ADT compiler and SAP runtime evidence as authoritative. If generic RAP examples or assumptions conflict with the target SAP system, follow the target system.
- Before implementing a change, read `PROJECT_STATUS.md`, `LEARNINGS.md`, and the documentation for the current phase/subphase.
- Work incrementally by documented phase and subphase.
- Do not proceed to the next subphase unless explicitly requested and after SAP runtime confirmation from the user.
- Preserve runtime-verified behavior. Do not rewrite working code unless the requested change requires it.
- Use managed RAP and EML for business-object operations.
- Do not use direct SQL `INSERT`, `UPDATE`, or `DELETE` on RAP persistence tables.
- Use read-only `SELECT` only when justified and documented.
- Do not assume handler instance state survives across RAP callbacks.
- Update `ZJP_CL_PO_EML_TEST` whenever RAP behavior changes.
- Mark a feature runtime-verified only after the user supplies SAP execution evidence.
- Use `PROJECT_STATUS.md` for current state, `LEARNINGS.md` for technical/runtime lessons, and `ARCHITECTURE.md` for architecture decisions.
- If previous chat memory conflicts with this repository or SAP runtime evidence, follow the repository and SAP evidence.
- Do not introduce future architecture components before their documented phase.
- Keep responses concise and report only:
  1. files changed;
  2. what was implemented;
  3. what the user must update or run in ADT;
  4. expected result.
  - Do not mark a subphase complete unless both the repository documentation and the latest SAP runtime evidence support that conclusion.