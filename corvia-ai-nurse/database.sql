/*
 ============================================================================
 Database: corvia_ai_nurse_intake
 Purpose:   AI nurse symptom intake with auto-urgency & recommendations
 ============================================================================
*/

-- CREATING THE DATABASE IF IT DOESN'T ALREADY EXIST
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = N'corvia_ai_nurse_intake')
BEGIN
    CREATE DATABASE corvia_ai_nurse_intake;
END;
GO

USE corvia_ai_nurse_intake;
GO

-- Drop existing tables (for clean re-run; comment in production)
IF OBJECT_ID('follow_up_actions', 'U') IS NOT NULL DROP TABLE follow_up_actions;
IF OBJECT_ID('ai_recommendations', 'U') IS NOT NULL DROP TABLE ai_recommendations;
IF OBJECT_ID('intake_symptoms', 'U') IS NOT NULL DROP TABLE intake_symptoms;
IF OBJECT_ID('severity_urgency_map', 'U') IS NOT NULL DROP TABLE severity_urgency_map;
IF OBJECT_ID('ai_symptom_intakes', 'U') IS NOT NULL DROP TABLE ai_symptom_intakes;
IF OBJECT_ID('symptoms', 'U') IS NOT NULL DROP TABLE symptoms;
IF OBJECT_ID('patients', 'U') IS NOT NULL DROP TABLE patients;
IF OBJECT_ID('urgency_levels', 'U') IS NOT NULL DROP TABLE urgency_levels;
GO

--CREATING THE TABLES
-- ============================================================================
-- 1. urgency_levels table
-- ============================================================================
CREATE TABLE urgency_levels (
    urgency_id   INT PRIMARY KEY IDENTITY(1,1),
    level_name   NVARCHAR(50) NOT NULL UNIQUE,
    description  NVARCHAR(MAX),
    color_code   NVARCHAR(10)
);
GO

-- ============================================================================
-- 2. patients table
-- ============================================================================
CREATE TABLE patients (
    patient_id      INT PRIMARY KEY IDENTITY(1,1),
    first_name      NVARCHAR(50) NOT NULL,
    last_name       NVARCHAR(50) NOT NULL,
    date_of_birth   DATE,
    gender          NVARCHAR(20) CHECK (gender IN (N'Male', N'Female', N'Non-Binary', N'Other', N'Prefer not to say')),
    id_number       NVARCHAR(20),
    passport_number NVARCHAR(20),
    contact_number  NVARCHAR(20),
    email           NVARCHAR(100),
    created_on      DATETIME DEFAULT GETDATE()
);
GO

-- Filtered Unique Indexes for nullable columns to allow multiple NULLs but enforce uniqueness for non-NULLs
CREATE UNIQUE INDEX UQ_patients_id_number ON patients(id_number) WHERE id_number IS NOT NULL;
CREATE UNIQUE INDEX UQ_patients_passport_number ON patients(passport_number) WHERE passport_number IS NOT NULL;
CREATE UNIQUE INDEX UQ_patients_contact_number ON patients(contact_number) WHERE contact_number IS NOT NULL;
CREATE UNIQUE INDEX UQ_patients_email ON patients(email) WHERE email IS NOT NULL;
GO

-- ============================================================================
-- 3. symptoms table
-- ============================================================================
CREATE TABLE symptoms (
    symptom_id       INT PRIMARY KEY IDENTITY(1,1),
    symptom_name     NVARCHAR(100) NOT NULL UNIQUE,
    symptom_category NVARCHAR(50),
    description      NVARCHAR(MAX)
);
GO

-- ============================================================================
-- 4. ai_symptom_intake table (Corrected name from ai_symptom_intakes as per ERD)
-- ============================================================================
CREATE TABLE ai_symptom_intakes (
    intake_id         INT PRIMARY KEY IDENTITY(1,1),
    patient_id        INT NOT NULL,
    urgency_id        INT NULL,
    intake_date       DATETIME DEFAULT GETDATE(), 
    chief_complaint   NVARCHAR(MAX) NOT NULL,
    notes             NVARCHAR(MAX),
    status            NVARCHAR(50) DEFAULT N'Pending' CHECK (status IN (N'Pending', N'Reviewed', N'Closed', N'Escalated')),
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE NO ACTION, 
    FOREIGN KEY (urgency_id) REFERENCES urgency_levels(urgency_id)
);
GO

-- ============================================================================
-- 5. intake_symptoms table (junction)
-- ============================================================================
CREATE TABLE intake_symptoms (
    intake_symptom_id INT PRIMARY KEY IDENTITY(1,1),
    intake_id         INT NOT NULL, 
    symptom_id        INT NOT NULL,
    severity          INT CHECK (severity BETWEEN 1 AND 10),
    duration          INT, 
    notes             NVARCHAR(MAX),
    FOREIGN KEY (intake_id) REFERENCES ai_symptom_intakes(intake_id) ON DELETE CASCADE,
    FOREIGN KEY (symptom_id) REFERENCES symptoms(symptom_id) ON DELETE NO ACTION,
    CONSTRAINT UQ_IntakeSymptom UNIQUE (intake_id, symptom_id)
);
GO

-- ============================================================================
-- 6. ai_recommendations table
-- ============================================================================
CREATE TABLE ai_recommendations (
    recommendation_id   INT PRIMARY KEY IDENTITY(1,1),
    intake_id           INT NOT NULL, 
    recommendation_text NVARCHAR(MAX) NOT NULL,
    recommended_by      NVARCHAR(100),
    confidence_score    DECIMAL(5,2) CHECK (confidence_score BETWEEN 0.00 AND 100.00),
    created_on          DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (intake_id) REFERENCES ai_symptom_intakes(intake_id) ON DELETE CASCADE
);
GO

-- ============================================================================
-- 7. follow_up_actions table
-- ============================================================================
CREATE TABLE follow_up_actions (
    action_id          INT PRIMARY KEY IDENTITY(1,1),
    intake_id          INT NOT NULL,
    action_description NVARCHAR(MAX) NOT NULL,
    action_type        NVARCHAR(50),
    action_status      NVARCHAR(50) DEFAULT N'Open' CHECK (action_status IN (N'Open', N'Completed', N'Cancelled', N'Closed')), 
    due_date           DATETIME,
    completed_date     DATETIME,
    assigned_to        NVARCHAR(100),
    FOREIGN KEY (intake_id) REFERENCES ai_symptom_intakes(intake_id) ON DELETE CASCADE
);
GO



-- ============================================================================
-- 8. severity_urgency_map table
-- ============================================================================
CREATE TABLE severity_urgency_map (
    map_id       INT PRIMARY KEY IDENTITY(1,1), 
    min_severity INT NOT NULL,
    max_severity INT NOT NULL,
    urgency_id   INT NOT NULL,
    FOREIGN KEY (urgency_id) REFERENCES urgency_levels(urgency_id),
    CHECK (min_severity >= 1 AND max_severity <= 10 AND min_severity <= max_severity),
    CONSTRAINT UQ_SeverityRange UNIQUE (min_severity, max_severity) -- Keep unique constraint on the range
);
GO


-- ============================================================================
-- TRIGGER: Auto-update urgency based on max symptom severity
-- ============================================================================
CREATE TRIGGER trg_intake_symptoms_update_urgency
ON intake_symptoms
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @affected TABLE (intake_id INT PRIMARY KEY); 
    INSERT INTO @affected (intake_id)
    SELECT intake_id FROM inserted
    UNION
    SELECT intake_id FROM deleted;

    UPDATE ai
    SET urgency_id = (
        SELECT TOP 1 m.urgency_id
        FROM (
            SELECT MAX(severity) AS max_sev
            FROM intake_symptoms
            WHERE intake_id = ai.intake_id
        ) AS max_sev
        INNER JOIN severity_urgency_map m
            ON max_sev.max_sev BETWEEN m.min_severity AND m.max_severity
    )
    FROM ai_symptom_intakes ai 
    WHERE ai.intake_id IN (SELECT intake_id FROM @affected) 
      AND EXISTS (SELECT 1 FROM intake_symptoms WHERE intake_id = ai.intake_id);
END;
GO

-- ============================================================================
-- STORED PROCEDURE: AI Nurse generates recommendation based on symptoms
-- ============================================================================
CREATE OR ALTER PROCEDURE GenerateAIRecommendation
    @intake_id INT 
AS
BEGIN
    SET NOCOUNT ON;
    
    IF NOT EXISTS (SELECT 1 FROM ai_symptom_intakes WHERE intake_id = @intake_id) 
    BEGIN
        RAISERROR('Intake ID %d does not exist.', 16, 1, @intake_id);
        RETURN;
    END

    DECLARE @max_severity INT;
    DECLARE @urgency_name NVARCHAR(50);
    DECLARE @chief_complaint NVARCHAR(MAX);
    DECLARE @recommendation_text NVARCHAR(MAX);
    DECLARE @confidence DECIMAL(5,2);

    SELECT TOP 1
        @max_severity = max_sev.max_sev,
        @urgency_name = u.level_name,
        @chief_complaint = i.chief_complaint
    FROM ai_symptom_intakes i 
    LEFT JOIN urgency_levels u ON i.urgency_id = u.urgency_id
    CROSS APPLY (
        SELECT MAX(severity) AS max_sev
        FROM intake_symptoms
        WHERE intake_id = i.intake_id 
    ) max_sev
    WHERE i.intake_id = @intake_id; 

    IF @urgency_name = N'Emergency'
    BEGIN
        SET @recommendation_text = N'URGENT: Based on symptoms (max severity ' + CAST(ISNULL(@max_severity, 0) AS NVARCHAR) + 
            N'), advise immediate ER visit or call 911. Chief complaint: ' + ISNULL(@chief_complaint, N'Not recorded');
        SET @confidence = 99.9;
    END
    ELSE IF @urgency_name = N'High'
    BEGIN
        SET @recommendation_text = N'Seek medical attention within 24 hours. Symptoms severity ' + 
            CAST(ISNULL(@max_severity, 0) AS NVARCHAR) + N'. ' + ISNULL(@chief_complaint, N'');
        SET @confidence = 90.0;
    END
    ELSE IF @urgency_name = N'Medium'
    BEGIN
        SET @recommendation_text = N'Schedule a doctor appointment within a few days. Monitor symptoms. ' + 
            ISNULL(@chief_complaint, N'');
        SET @confidence = 80.0;
    END
    ELSE
    BEGIN
        SET @recommendation_text = N'Self-care at home: rest, hydration, OTC medication as needed. ' + 
            ISNULL(@chief_complaint, N'');
        SET @confidence = 70.0;
    END

    INSERT INTO ai_recommendations (intake_id, recommendation_text, recommended_by, confidence_score)
    VALUES (@intake_id, @recommendation_text, N'AI Nurse v2.0', @confidence);
END;
GO

-- ============================================================================
-- INSERT SAMPLE DATA INTO TABLE
-- ============================================================================

-- 1. Urgency levels (auto-increment)
INSERT INTO urgency_levels (level_name, description, color_code) VALUES
(N'Low',       N'Non-urgent, can be managed at home or routine appointment.', N'#2ECC71'),
(N'Medium',    N'Requires medical attention within a few days.', N'#F39C12'),
(N'High',      N'Requires prompt medical attention within 24 hours.', N'#E74C3C'),
(N'Emergency', N'Immediate life-threatening condition, go to ER or call 10177.', N'#8E44AD');
GO

-- 2. Severity mapping
INSERT INTO severity_urgency_map (min_severity, max_severity, urgency_id) VALUES
(1, 3, 1), 
(4, 6, 2), 
(7, 8, 3), 
(9, 10, 4);
GO

-- 3. Patients 
-- patients with SA ID, patients with passport
-- Patients with SA ID numbers (6) 
-- Synthetic portfolio fixtures; no real patient identities.
INSERT INTO patients (first_name, last_name, date_of_birth, gender, id_number, passport_number, contact_number, email, created_on) VALUES
(N'Demo', N'Patient1', '2000-01-01', N'Prefer not to say', N'DEMO-ID-1', NULL, NULL, N'patient1@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient2', '2000-01-01', N'Prefer not to say', N'DEMO-ID-2', NULL, NULL, N'patient2@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient3', '2000-01-01', N'Prefer not to say', N'DEMO-ID-3', NULL, NULL, N'patient3@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient4', '2000-01-01', N'Prefer not to say', N'DEMO-ID-4', NULL, NULL, N'patient4@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient5', '2000-01-01', N'Prefer not to say', N'DEMO-ID-5', NULL, NULL, N'patient5@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient6', '2000-01-01', N'Prefer not to say', N'DEMO-ID-6', NULL, NULL, N'patient6@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient7', '2000-01-01', N'Prefer not to say', N'DEMO-ID-7', NULL, NULL, N'patient7@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient8', '2000-01-01', N'Prefer not to say', N'DEMO-ID-8', NULL, NULL, N'patient8@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient9', '2000-01-01', N'Prefer not to say', N'DEMO-ID-9', NULL, NULL, N'patient9@example.invalid', '2023-09-20 10:00:00'),
(N'Demo', N'Patient10', '2000-01-01', N'Prefer not to say', N'DEMO-ID-10', NULL, NULL, N'patient10@example.invalid', '2023-09-20 10:00:00');
GO

-- 4. Symptoms 
INSERT INTO symptoms (symptom_name, symptom_category, description) VALUES
(N'Headache', N'Neurological', N'Pain in any region of the head.'),
(N'Fever', N'General', N'Temporary increase in body temperature.'),
(N'Cough', N'Respiratory', N'Forceful hacking sound to clear irritation.'),
(N'Fatigue', N'General', N'Overall tiredness or lack of energy.'),
(N'Nausea', N'Gastrointestinal', N'Stomach discomfort and urge to vomit.'),
(N'Vomiting', N'Gastrointestinal', N'Forcible emptying of stomach contents.'),
(N'Shortness of Breath', N'Respiratory', N'Intense chest tightening, difficulty breathing.'),
(N'Chest Pain', N'Cardiovascular', N'Crushing or burning chest discomfort.'),
(N'Dizziness', N'Neurological', N'Feeling faint, woozy, or unsteady.'),
(N'Sore Throat', N'Respiratory', N'Pain or irritation in the throat.'),
(N'Runny Nose', N'Respiratory', N'Excess nasal drainage.'),
(N'Muscle Ache', N'Musculoskeletal', N'General muscle pain.'),
(N'Joint Pain', N'Musculoskeletal', N'Pain or inflammation in joints.'),
(N'Rash', N'Dermatological', N'Change in skin texture or color.'),
(N'Abdominal Pain', N'Gastrointestinal', N'Pain between chest and pelvis.'),
(N'Diarrhea', N'Gastrointestinal', N'Loose, watery stools.'),
(N'Constipation', N'Gastrointestinal', N'Infrequent or difficult bowel movements.'),
(N'Loss of Taste', N'Sensory', N'Partial or complete loss of taste.'),
(N'Loss of Smell', N'Sensory', N'Partial or complete loss of smell.'),
(N'Chills', N'General', N'Feeling cold during fever.');
GO

-- 5. ai_symptoms_intakes (auto-increment intake_id)
INSERT INTO ai_symptom_intakes (patient_id, urgency_id, intake_date, chief_complaint, notes, status) VALUES
(1, NULL, '2023-10-01 08:30:00', N'Headache and tiredness after long shift', N'Themba reports mild headache and fatigue.', N'Pending'),
(2, NULL, '2023-10-02 09:15:00', N'Severe stomach pain since last night', N'Priya has severe abdominal pain.', N'Pending'),
(3, NULL, '2023-10-03 10:00:00', N'Crushing chest pain and difficulty breathing', N'Johannes – possible heart attack.', N'Escalated'),
(4, NULL, '2023-10-04 11:45:00', N'Persistent cough and low fever', N'Kamohelo has dry cough for 5 days.', N'Pending'),
(5, NULL, '2023-10-05 14:20:00', N'Runny nose and sore throat', N'Jusuf – seasonal allergies.', N'Pending'),
(6, NULL, '2023-10-06 16:10:00', N'Sudden dizziness and slurred speech', N'Nandipha – possible stroke.', N'Escalated'),
(7, NULL, '2023-10-07 18:05:00', N'Nausea and vomiting for 12 hours', N'André unable to keep fluids down.', N'Pending'),
(8, NULL, '2023-10-08 07:50:00', N'High fever and severe body aches', N'Fatima – fever of 39°C.', N'Pending'),
(9, NULL, '2023-10-09 12:30:00', N'Small rash on arm', N'Siphosihle – itchy red bumps.', N'Reviewed'),
(10, NULL, '2023-10-10 15:40:00', N'Chronic joint pain flare-up', N'Chantelle – pain in knees and hips.', N'Reviewed'),
(1, NULL, '2023-10-11 09:00:00', N'Lost taste and smell suddenly', N'Themba – possible COVID-19.', N'Pending'),
(2, NULL, '2023-10-12 10:20:00', N'Difficulty breathing after bee sting', N'Priya – allergic reaction.', N'Escalated'),
(3, NULL, '2023-10-13 11:15:00', N'Mild diarrhoea for 2 days', N'Johannes – loose stools 3-4 times/day.', N'Pending'),
(4, NULL, '2023-10-14 13:45:00', N'Severe migraine not responding to meds', N'Kamohelo – throbbing behind eyes.', N'Pending'),
(5, NULL, '2023-10-15 16:30:00', N'Always tired and feeling cold', N'Jusuf – fatigue for 2 weeks.', N'Pending');
GO

-- 6. Symptoms for each intake (trigger will set urgency automatically)
INSERT INTO intake_symptoms (intake_id, symptom_id, severity, duration, notes) VALUES
(1, 1, 3, 2, N'Throbbing headache'),
(1, 4, 4, 3, N'Constant tiredness'),
(2, 15, 8, 1, N'Sharp lower abdominal pain'),
(2, 5, 6, 1, N'Nausea'),
(3, 8, 9, 1, N'Crushing chest pain'),
(3, 7, 8, 1, N'Cannot catch breath'),
(4, 3, 5, 5, N'Dry cough'),
(4, 2, 4, 2, N'Low-grade fever'),
(5, 11, 3, 3, N'Runny nose'),
(5, 10, 4, 3, N'Scratchy throat'),
(6, 9, 9, 1, N'Room spinning'),
(7, 5, 7, 1, N'Constant nausea'),
(7, 6, 7, 1, N'Vomited twice'),
(8, 2, 8, 2, N'Fever 39°C'),
(8, 12, 7, 2, N'Muscle aches everywhere'),
(9, 14, 3, 4, N'Small red bumps on forearm'),
(10, 13, 6, 14, N'Pain in knees and hips'),
(11, 18, 5, 3, N'Food tastes bland'),
(11, 19, 5, 3, N'Cannot smell anything'),
(12, 7, 10, 1, N'Wheezing, gasping for air'),
(12, 14, 8, 1, N'Hives all over'),
(13, 16, 4, 2, N'Loose stools'),
(14, 1, 9, 1, N'Blinding headache behind eyes'),
(14, 5, 5, 1, N'Nauseous'),
(15, 4, 6, 7, N'Exhausted after sleep'),
(15, 20, 5, 2, N'Shivering and cold');
GO

-- Generate AI recommendations for all intakes
BEGIN TRY
    EXEC GenerateAIRecommendation 1;
    EXEC GenerateAIRecommendation 2;
    EXEC GenerateAIRecommendation 3;
    EXEC GenerateAIRecommendation 4;
    EXEC GenerateAIRecommendation 5;
    EXEC GenerateAIRecommendation 6;
    EXEC GenerateAIRecommendation 7;
    EXEC GenerateAIRecommendation 8;
    EXEC GenerateAIRecommendation 9;
    EXEC GenerateAIRecommendation 10;
    EXEC GenerateAIRecommendation 11;
    EXEC GenerateAIRecommendation 12;
    EXEC GenerateAIRecommendation 13;
    EXEC GenerateAIRecommendation 14;
    EXEC GenerateAIRecommendation 15;
END TRY
BEGIN CATCH
    PRINT 'Error generating AI recommendations: ' + ERROR_MESSAGE();
END CATCH
GO

-- 7. Follow-up actions (auto-increment action_id)
INSERT INTO follow_up_actions (intake_id, action_description, action_type, action_status, due_date, completed_date, assigned_to) VALUES
(1, N'No follow-up needed unless symptoms worsen', N'None', N'Closed', NULL, GETDATE(), N'AI Nurse'),
(2, N'Nurse to call Priya to check progression', N'Call', N'Open', DATEADD(DAY, 1, GETDATE()), NULL, N'Sister Nomsa'),
(3, N'Immediate emergency dispatch – possible MI', N'Escalate', N'Completed', GETDATE(), GETDATE(), N'System'),
(4, N'Schedule follow-up appointment with GP', N'Appointment', N'Open', DATEADD(DAY, 7, GETDATE()), NULL, N'Admin Staff'),
(5, N'No follow-up required', N'None', N'Closed', NULL, GETDATE(), N'AI Nurse'),
(6, N'Immediate stroke alert – ambulance dispatched', N'Escalate', N'Completed', GETDATE(), GETDATE(), N'System'),
(7, N'Automated SMS check-in via DEMO-CONTACT', N'SMS', N'Open', DATEADD(DAY, 2, GETDATE()), NULL, N'AI Nurse'),
(8, N'Nurse to call Fatima for high fever', N'Call', N'Open', DATEADD(DAY, 1, GETDATE()), NULL, N'Sister Thandi'),
(9, N'Monitor rash; no action needed', N'None', N'Closed', NULL, GETDATE(), N'AI Nurse'),
(10, N'Schedule rheumatology appointment', N'Appointment', N'Open', DATEADD(DAY, 14, GETDATE()), NULL, N'Admin Staff'),
(11, N'SMS check-in for sensory loss', N'SMS', N'Open', DATEADD(DAY, 3, GETDATE()), NULL, N'AI Nurse'),
(12, N'Emergency allergy response – ER notified', N'Escalate', N'Completed', GETDATE(), GETDATE(), N'System'),
(13, N'No follow-up', N'None', N'Closed', NULL, GETDATE(), N'AI Nurse'),
(14, N'Nurse to call Lerato for migraine', N'Call', N'Open', DATEADD(DAY, 1, GETDATE()), NULL, N'Sister Nomsa'),
(15, N'Schedule primary care for fatigue', N'Appointment', N'Open', DATEADD(DAY, 7, GETDATE()), NULL, N'Admin Staff');
GO

-- ============================================================================
-- REQUIRED SQL OPERATIONS (with transaction for data integrity)
-- ============================================================================

BEGIN TRANSACTION;
BEGIN TRY
    -- 1. Insert a new symptom intake for a new patient
    INSERT INTO patients (first_name, last_name, date_of_birth, gender, id_number, passport_number, contact_number, email) 
    VALUES (N'Siya', N'Cele', '1990-11-05', N'Male', N'DEMO-ID-11', NULL, NULL, N'demo11@example.invalid');
    
    DECLARE @new_patient_id INT = SCOPE_IDENTITY();

    INSERT INTO ai_symptom_intakes (patient_id, chief_complaint, notes) 
    VALUES (@new_patient_id, N'Chest tightness after exercise', N'Siya – feels pressure but not severe');

    DECLARE @new_intake_id INT = SCOPE_IDENTITY();

    -- Link symptoms to the new intake
    INSERT INTO intake_symptoms (intake_id, symptom_id, severity) 
    VALUES (@new_intake_id, 8, 6);  -- chest pain severity 6

    INSERT INTO intake_symptoms (intake_id, symptom_id, severity) 
    VALUES (@new_intake_id, 7, 4);  -- shortness of breath severity 4

    -- 2. Update urgency level for this new intake (trigger will also set based on max severity)
    -- The trigger trg_intake_symptoms_update_urgency will handle this automatically after intake_symptoms insert.
    UPDATE ai_symptom_intakes SET urgency_id = (SELECT urgency_id FROM urgency_levels WHERE level_name = N'Medium') WHERE intake_id = @new_intake_id;

    -- 3. Add AI recommendation for the new intake
    EXEC GenerateAIRecommendation @new_intake_id;

    COMMIT TRANSACTION;
    PRINT 'New intake and associated data inserted successfully.';
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    PRINT 'Error in required operations: ' + ERROR_MESSAGE();
END CATCH
GO

--Show all from the ai_symptom_intakes table
SELECT * FROM ai_symptom_intakes;
GO

--Show all from the patients table
SELECT * FROM patients;
GO

-- 4. Show emergency cases of patients
SELECT i.intake_id, p.first_name, p.last_name, p.contact_number, u.level_name, i.chief_complaint
FROM ai_symptom_intakes i
JOIN patients p ON i.patient_id = p.patient_id
JOIN urgency_levels u ON i.urgency_id = u.urgency_id
WHERE u.level_name = N'Emergency';
GO

-- 5. Show open follow-up actions
SELECT f.action_id, p.first_name, p.last_name, p.contact_number, f.action_description, f.due_date, f.assigned_to
FROM follow_up_actions f
JOIN ai_symptom_intakes i ON f.intake_id = i.intake_id
JOIN patients p ON i.patient_id = p.patient_id
WHERE f.action_status = N'Open';
GO

-- ============================================================================
-- REQUIRED REPORTS (JOIN queries)
-- ============================================================================

-- Report 1: Patient name, symptoms, urgency, AI recommendation, follow-up action
SELECT 
    p.first_name + ' ' + p.last_name AS patient_name,
    p.contact_number,
    STRING_AGG(s.symptom_name, ', ') AS symptoms,
    u.level_name AS urgency,
    ar.recommendation_text AS ai_recommendation,
    fa.action_description AS follow_up_action
FROM patients p
JOIN ai_symptom_intakes i ON p.patient_id = i.patient_id
LEFT JOIN intake_symptoms ins ON i.intake_id = ins.intake_id
LEFT JOIN symptoms s ON ins.symptom_id = s.symptom_id
LEFT JOIN urgency_levels u ON i.urgency_id = u.urgency_id
LEFT JOIN ai_recommendations ar ON i.intake_id = ar.intake_id
LEFT JOIN follow_up_actions fa ON i.intake_id = fa.intake_id
GROUP BY p.patient_id, i.intake_id, u.level_name, ar.recommendation_text, fa.action_description, p.first_name, p.last_name, p.contact_number
ORDER BY i.intake_id;
GO

-- Report 2: All emergency intakes
SELECT i.intake_id, p.first_name + ' ' + p.last_name AS patient, 
       p.contact_number, i.chief_complaint, i.intake_date, u.color_code,
       (SELECT MAX(severity) FROM intake_symptoms WHERE intake_id = i.intake_id) AS max_severity
FROM ai_symptom_intakes i
JOIN patients p ON i.patient_id = p.patient_id
JOIN urgency_levels u ON i.urgency_id = u.urgency_id
WHERE u.level_name = N'Emergency';
GO

-- Report 3: All intakes for Themba Nkosi (patient_id = 1)
SELECT i.intake_id, i.intake_date, i.chief_complaint, 
       (SELECT MAX(severity) FROM intake_symptoms WHERE intake_id = i.intake_id) AS max_severity,
       u.level_name, i.status
FROM ai_symptom_intakes i
LEFT JOIN urgency_levels u ON i.urgency_id = u.urgency_id
WHERE i.patient_id = 1
ORDER BY i.intake_date DESC;
GO

-- Report 4: Most common symptoms (top 5)
SELECT TOP 5 s.symptom_name, COUNT(ins.intake_id) AS occurrence_count
FROM symptoms s
JOIN intake_symptoms ins ON s.symptom_id = ins.symptom_id
GROUP BY s.symptom_id, s.symptom_name
ORDER BY occurrence_count DESC;
GO

-- Additional JOIN: Average severity per urgency level
SELECT u.level_name, AVG(CAST(ins.severity AS FLOAT)) AS avg_severity
FROM urgency_levels u
JOIN ai_symptom_intakes i ON u.urgency_id = i.urgency_id
JOIN intake_symptoms ins ON i.intake_id = ins.intake_id
GROUP BY u.level_name
ORDER BY avg_severity DESC;
GO

--  Add the column
ALTER TABLE ai_symptom_intakes 
ADD submitted_at DATETIME NULL;
GO

-- Create the trigger
CREATE TRIGGER trg_intake_submitted_at
ON ai_symptom_intakes
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE i
    SET submitted_at = GETDATE()
    FROM ai_symptom_intakes i
    INNER JOIN inserted ins ON i.intake_id = ins.intake_id
    INNER JOIN deleted del ON i.intake_id = del.intake_id
    WHERE del.status = N'Pending' 
      AND ins.status <> N'Pending'
      AND i.submitted_at IS NULL;
END;
GO

-- Backfill existing submitted intakes
UPDATE ai_symptom_intakes 
SET submitted_at = intake_date 
WHERE status <> N'Pending' AND submitted_at IS NULL;

INSERT INTO ai_symptom_intakes (patient_id, chief_complaint, notes, status)
VALUES (1, N'My symptoms...', N'Draft notes', N'Pending');

UPDATE ai_symptom_intakes 
SET status = N'Reviewed'   
WHERE intake_id = 1;

SELECT intake_id, patient_id, intake_date, submitted_at, status, 
       DATEDIFF(MINUTE, intake_date, submitted_at) AS minutes_to_submit
FROM ai_symptom_intakes 
WHERE submitted_at IS NOT NULL;

-- Check the index
EXEC sp_helpindex 'ai_symptom_intakes';

-- Example query that will now be faster
SELECT * FROM ai_symptom_intakes 
WHERE submitted_at IS NOT NULL 
ORDER BY submitted_at DESC;
