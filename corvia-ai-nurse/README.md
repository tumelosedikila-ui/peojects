# Corvia AI Nurse Intake Database

Recovered from Tumelo Sedikila's original academic SQL Server project. Demonstrates eight relational tables, constraints, indexes, a severity mapping trigger, a simulated recommendation procedure and reporting queries. This is an educational database demonstration, not a clinical application or a trained AI model.

## Run

Use SQL Server with SQL Server Management Studio. Open database.sql and execute against a disposable development instance. The script creates corvia_ai_nurse_intake and drops/recreates its tables on subsequent runs. Do not run it against a database containing data you need.

The copied script uses synthetic identity/contact fixtures. Original documents remain in your Documents folder and are excluded from this repository. Recovery fixes correct the intake table existence check and add the batch separator required before CREATE TRIGGER.

## Validation

Source reviewed; execution on SQL Server has not yet been verified.
