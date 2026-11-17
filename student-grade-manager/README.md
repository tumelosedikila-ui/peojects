# Student Grade Manager

Recovered original C# academic console application by Tumelo Sedikila. Uses a list to record grades, display saved marks and calculate an average, with menu and input validation. Grades are kept in memory for the current session.

## Run

Install the .NET 10 SDK or later, then run:

    dotnet run --project GradeManagementSystem.csproj

Choose 1 to view grades, 2 to add a mark from 0 to 100, 3 for the class average, or 4 to exit.

Source recovered from Documents/Formative Assessment/Formative Assessment1; original files are preserved.

Recovery improvements: formatted the original program, handle end-of-input cleanly, reject NaN/infinite marks, and use dot-decimal input consistently.

Validation: .NET 10 build passed with zero warnings/errors. Automated console checks cover empty lists, adding/displaying grades, averages, invalid menu input, out-of-range and non-finite marks, and end-of-input.
