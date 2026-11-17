# Portfolio Projects

Software and database projects by Tumelo Sammy Sedikila, recovered from original academic source files and prepared for GitHub.

| Project | Technology | Start here |
| --- | --- | --- |
| [Student Grade Manager](student-grade-manager/) | C# / .NET 10 | Console application for recording grades and calculating averages |
| [Corvia AI Nurse](corvia-ai-nurse/) | SQL Server / T-SQL | Academic relational database with simulated recommendations |

MineReady has its own repository: https://github.com/tumelosedikila-ui/MineReady

Original source files remain unchanged in the Documents folder. See each project's README for setup, recovery fixes and validation limits.

## Verify

Build with `dotnet build student-grade-manager/GradeManagementSystem.csproj`, then run `node scripts/verify.mjs` (Node.js 20+). This runs the C# console checks and static SQL checks. Corvia still requires a SQL Server execution check.
