using System.Globalization;

var grades = new List<double>();
while (true)
{
    Console.WriteLine("\n=== Student Grade Management System ===");
    Console.WriteLine("1. View All Grades\n2. Add a New Grade\n3. Calculate Average Grade\n4. Exit");
    Console.Write("Enter your choice (1-4): ");
    var input = Console.ReadLine();
    if (input is null || input == "4")
    {
        Console.WriteLine("Exiting system. Goodbye!");
        break;
    }
    if (!int.TryParse(input, out var choice) || choice < 1 || choice > 4)
    {
        Console.WriteLine("Error: Invalid input. Please enter a number between 1 and 4.");
        continue;
    }
    switch (choice)
    {
        case 1:
            if (grades.Count == 0) Console.WriteLine("No grades available.");
            else for (var i = 0; i < grades.Count; i++)
                Console.WriteLine(FormattableString.Invariant($"Grade {i + 1}: {grades[i]:F2}"));
            break;
        case 2:
            Console.Write("Enter a grade (0-100): ");
            var gradeInput = Console.ReadLine();
            if (gradeInput is null) return;
            if (!double.TryParse(gradeInput, NumberStyles.Float, CultureInfo.InvariantCulture, out var grade)
                || !double.IsFinite(grade) || grade < 0 || grade > 100)
                Console.WriteLine("Error: Invalid grade. Please enter a number between 0 and 100 (use a dot for decimals).");
            else
            {
                grades.Add(grade);
                Console.WriteLine(FormattableString.Invariant($"Grade {grade:F2} added successfully."));
            }
            break;
        case 3:
            Console.WriteLine(grades.Count == 0 ? "No grades available to calculate average."
                : FormattableString.Invariant($"Average Grade: {grades.Average():F2}"));
            break;
    }
}
