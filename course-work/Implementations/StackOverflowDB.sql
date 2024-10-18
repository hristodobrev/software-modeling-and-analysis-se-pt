------------ DATABASE ------------
USE master;
GO

IF  EXISTS (SELECT name FROM sys.databases WHERE name = N'StackOverflowDB')
BEGIN
	ALTER DATABASE StackOverflowDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

	DROP DATABASE IF EXISTS StackOverflowDB;
END
GO

CREATE DATABASE StackOverflowDB;
GO

USE StackOverflowDB;
GO

CREATE SCHEMA [User];
GO

CREATE SCHEMA Question;
GO

------------ TABLES ------------
CREATE TABLE [User].[User] (
	Id INT IDENTITY(1, 1) NOT NULL,
	Title VARCHAR(20) NOT NULL,
	FirstName VARCHAR(50) NULL,
	LastName VARCHAR(50) NOT NULL,
	Phone VARCHAR(20) NULL,
	Email VARCHAR(200) NOT NULL,
	Rating INT NOT NULL CONSTRAINT DF_User_Rating DEFAULT 0,

	CONSTRAINT PK_User_Id PRIMARY KEY (Id),
	CONSTRAINT UQ_User_Email UNIQUE (Email)
);
GO

CREATE TABLE [User].SaveList (
	Id INT IDENTITY(1, 1) NOT NULL,
	[Name] VARCHAR(50) NOT NULL,
	UserId INT NOT NULL,

	CONSTRAINT PK_SaveList_Id PRIMARY KEY (Id),
	CONSTRAINT FK_SaveList_UserId FOREIGN KEY (UserId) REFERENCES [User].[User](Id)
);
GO

CREATE TABLE Question.Question (
	Id INT IDENTITY(1, 1) NOT NULL,
	Title VARCHAR(100) NOT NULL,
	[Description] VARCHAR(1000) NOT NULL,
	[Views] INT NOT NULL CONSTRAINT DF_Question_Views DEFAULT 0,
	Upvotes INT NOT NULL CONSTRAINT DF_Question_Upvotes DEFAULT 0,
	Downvotes INT NOT NULL CONSTRAINT DF_Question_Downvotes DEFAULT 0,
	CreateDate DATETIME NOT NULL CONSTRAINT DF_Question_DateCreated DEFAULT GETDATE(),
	AnswerId INT NULL,
	SaveListId INT NULL,
	UserId INT NOT NULL,

	CONSTRAINT PK_Question_Id PRIMARY KEY (Id),
	CONSTRAINT FK_Question_SaveListId FOREIGN KEY (SaveListId) REFERENCES [User].SaveList(Id),
	CONSTRAINT FK_Question_UserId FOREIGN KEY (UserId) REFERENCES [User].[User](Id)
);
GO

CREATE TABLE Question.Answer (
	Id INT IDENTITY(1, 1) NOT NULL,
	[Text] VARCHAR(1000) NOT NULL,
	Upvotes INT NOT NULL CONSTRAINT DF_Answer_Upvotes DEFAULT 0,
	Downvotes INT NOT NULL CONSTRAINT DF_Answer_Downvotes DEFAULT 0,
	CreateDate DATETIME NOT NULL CONSTRAINT DF_Answer_DateCreated DEFAULT GETDATE(),
	QuestionId INT NULL,
	UserId INT NOT NULL,

	CONSTRAINT PK_Answer_Id PRIMARY KEY (Id),
	CONSTRAINT FK_Answer_QuestionId FOREIGN KEY (QuestionId) REFERENCES Question.Question(Id),
	CONSTRAINT FK_Answer_UserId FOREIGN KEY (UserId) REFERENCES [User].[User](Id)
);
GO

ALTER TABLE Question.Question
ADD CONSTRAINT FK_Question_AnswerId FOREIGN KEY (AnswerId) REFERENCES Question.Answer(Id);
GO

CREATE TABLE [User].Badge (
	Id INT IDENTITY(1, 1) NOT NULL,
	[Name] VARCHAR(50) NOT NULL,
	RequiredRating INT NOT NULL CONSTRAINT DF_Badge_RequiredRating DEFAULT 0,

	CONSTRAINT PK_Badge_Id PRIMARY KEY (Id),
	CONSTRAINT UQ_Badge_Name UNIQUE ([Name])
);
GO

CREATE TABLE [User].UserBadge (
	UserId INT NOT NULL,
	BadgeId INT NOT NULL,

	CONSTRAINT FK_UserBadge_UserId FOREIGN KEY (UserId) REFERENCES [User].[User](Id),
	CONSTRAINT FK_UserBadge_BadgeId FOREIGN KEY (BadgeId) REFERENCES [User].Badge(Id),
	CONSTRAINT UQ_UserBadge_UserId_BadgeId UNIQUE (UserId, BadgeId)
);
GO

CREATE TABLE Question.Tag (
	Id INT IDENTITY(1, 1) NOT NULL,
	[Name] VARCHAR(50) NOT NULL,
	EarnedRating INT NOT NULL CONSTRAINT DF_Tag_EarnedRating DEFAULT 0,

	CONSTRAINT PK_Tag_Id PRIMARY KEY (Id),
	CONSTRAINT UQ_Tag_Name UNIQUE ([Name])
);
GO

CREATE TABLE Question.QuestionTag (
	QuestionId INT NOT NULL,
	TagId INT NOT NULL,

	CONSTRAINT FK_QuestionTag_UserId FOREIGN KEY (QuestionId) REFERENCES Question.Question(Id),
	CONSTRAINT FK_QuestionTag_BadgeId FOREIGN KEY (TagId) REFERENCES Question.Tag(Id),
	CONSTRAINT UQ_QuestionTag_UserId_BadgeId UNIQUE (QuestionId, TagId)
);
GO

------------ FUNCTIONS ------------
CREATE OR ALTER FUNCTION Question.F_QuestionRating
(
	@QuestionId INT
)
RETURNS INT
AS
BEGIN
	DECLARE @Rating INT;

	SELECT @Rating = SUM(EarnedRating)
	FROM Question.Tag t
		INNER JOIN Question.QuestionTag qt ON qt.QuestionId = t.Id
		INNER JOIN Question.Question q ON q.Id = qt.QuestionId
	WHERE q.Id = @QuestionId

	RETURN @Rating
END
GO

CREATE OR ALTER FUNCTION [User].F_GetSavedLists
(
	@UserId INT
)
RETURNS TABLE
AS
RETURN

	SELECT sl.Name, COUNT(1) AS QuestionsCount
	FROM [User].SaveList sl
		INNER JOIN Question.Question q ON q.SaveListId = sl.Id
	WHERE sl.UserId = @UserId
	GROUP BY sl.Name
GO

------------ TRIGGERS ------------
CREATE OR ALTER TRIGGER Question.TR_ForUpdateQuestion
ON Question.Question
FOR UPDATE
AS
BEGIN
	-- When question has been updated with correct answer, increase the user rating by the rating earned from the tags of that question
	UPDATE u
	SET Rating = Rating + Question.F_QuestionRating(q.Id)
	FROM [User].[User] u
		INNER JOIN Question.Question q ON q.UserId = u.Id
		INNER JOIN deleted d ON d.Id = q.Id
		INNER JOIN inserted i ON i.Id = d.Id
	WHERE d.AnswerId IS NULL AND i.AnswerId != 0
END
GO

CREATE OR ALTER TRIGGER Question.TR_ForInsertAnswer
ON Question.Answer
FOR INSERT
AS
BEGIN
	-- Increase user rating when they post answer to some question
	-- Rating must be increased by the product of all the answers inserted from given user)
	UPDATE u
	SET Rating = Rating + (SELECT COUNT(1) * 5 FROM inserted i WHERE i.UserId = u.id)
	FROM inserted i
		INNER JOIN [User].[User] u ON u.Id = i.UserId
END
GO

CREATE OR ALTER TRIGGER [User].TR_ForUpdateUser
ON [User].[User]
FOR UPDATE
AS
BEGIN
	-- When user rating has been updated, check if they should receive a badge
	DECLARE @userBadges TABLE(
		UserId INT, 
		BadgeId INT
	);

	INSERT INTO @userBadges
	SELECT i.Id, b.Id
	FROM inserted i
		INNER JOIN Badge b ON i.Rating >= b.RequiredRating
	WHERE NOT EXISTS (SELECT 1 FROM UserBadge ub WHERE ub.UserId = i.Id and b.Id = ub.BadgeId)

	INSERT INTO UserBadge (UserId, BadgeId)
	SELECT *
	FROM @userBadges

	DECLARE @message VARCHAR(1000);
	SELECT @message = STRING_AGG(u.Title + ' ' + u.LastName + ' earned badge ' + b.Name, CHAR(13))
	FROM @userBadges ub
		INNER JOIN [User].[User] u ON u.Id = ub.UserId
		INNER JOIN [User].Badge b ON b.Id = ub.BadgeId

	PRINT(@message)
END
GO
------------ PROCEDURES ------------
CREATE OR ALTER PROCEDURE Question.USP_GetQuestionsWithAnswers
AS
BEGIN

	SELECT q.Title AS Question, q.Description, q.CreateDate AS QuestionDate, CONCAT(qu.Title, ' ', qu.FirstName, ' ', qu.LastName) AS AskedBy, a.Text AS Answer, a.CreateDate AS AnswerDate, CONCAT(au.Title, ' ', au.FirstName, ' ', au.LastName) as AnsweredBy, STRING_AGG(t.Name, ', ') AS Tags
	FROM Question.Question q
		LEFT JOIN Question.Answer a ON a.QuestionId = q.Id
		LEFT JOIN Question.QuestionTag qt ON qt.QuestionId = q.Id
		LEFT JOIN Question.Tag t ON t.Id = qt.TagId
		INNER JOIN [User].[User] qu ON qu.Id = q.UserId
		INNER JOIN [User].[User] au ON au.Id = a.UserId
	GROUP BY q.Title, q.Description, q.CreateDate, CONCAT(qu.Title, ' ', qu.FirstName, ' ', qu.LastName), a.Text, a.CreateDate, CONCAT(au.Title, ' ', au.FirstName, ' ', au.LastName)
	ORDER BY q.CreateDate DESC, a.CreateDate DESC

END
GO

CREATE OR ALTER PROCEDURE Question.USP_GetUsersQuestions
(@UserId INT)
AS
BEGIN

	SELECT q.Title AS Question, q.Description, q.CreateDate AS QuestionDate, CONCAT(qu.Title, ' ', qu.FirstName, ' ', qu.LastName) AS AskedBy, a.Text AS Answer, a.CreateDate AS AnswerDate, CONCAT(au.Title, ' ', au.FirstName, ' ', au.LastName) as AnsweredBy, STRING_AGG(t.Name, ', ') AS Tags
	FROM Question.Question q
		LEFT JOIN Question.Answer a ON a.QuestionId = q.Id
		LEFT JOIN Question.QuestionTag qt ON qt.QuestionId = q.Id
		LEFT JOIN Question.Tag t ON t.Id = qt.TagId
		INNER JOIN [User].[User] qu ON qu.Id = q.UserId
		INNER JOIN [User].[User] au ON au.Id = a.UserId
	WHERE q.UserId = @UserId
	GROUP BY q.Title, q.Description, q.CreateDate, CONCAT(qu.Title, ' ', qu.FirstName, ' ', qu.LastName), a.Text, a.CreateDate, CONCAT(au.Title, ' ', au.FirstName, ' ', au.LastName)
	ORDER BY q.CreateDate DESC, a.CreateDate DESC

END
GO

CREATE OR ALTER PROCEDURE [User].USP_GetUsersStatistics
AS
BEGIN
	SELECT CONCAT(u.Title, ' ', u.FirstName, ' ', u.LastName) AS [User], u.Rating, Questions.QuestionsCount, Answers.AnswersCount, Badges.BadgesCount
	FROM [User].[User] u
		CROSS APPLY (SELECT COUNT(1) AS QuestionsCount FROM Question.Question WHERE UserId = u.Id) Questions
		CROSS APPLY (SELECT COUNT(1) AS AnswersCount FROM Question.Answer WHERE UserId = u.Id) Answers
		CROSS APPLY (SELECT COUNT(1) AS BadgesCount FROM [User].UserBadge WHERE UserId = u.Id) Badges
END
GO
------------ FEED DB WITH DATA ------------
INSERT INTO [User].[User] (Title, FirstName, LastName, Phone, Email)
VALUES 
('Mr', 'John', 'Doe', '555-1234', 'john.doe@example.com'),
('Ms', NULL, 'Smith', NULL, 'jane.smith@example.com'),
('Dr', 'Alice', 'Brown', '555-9876', 'alice.brown@example.com'),
('Mr', 'Bob', 'Johnson', NULL, 'bob.johnson@example.com'),
('Prof', NULL, 'Williams', NULL, 'williams.prof@example.com'),
('Mr', 'Carlos', 'Gomez', '555-3333', 'carlos.gomez@example.net'),
('Mrs', 'Emily', 'Clark', '555-8888', 'emily.clark@example.org'),
('Mr', 'Tom', 'Baker', '555-2222', 'tom.baker@example.com'),
('Ms', 'Sara', 'Miller', '555-4444', 'sara.miller@example.com'),
('Mr', 'David', 'Lee', '555-5555', 'david.lee@example.org');
GO

INSERT INTO [User].SaveList ([Name], UserId)
VALUES
('My Favorite Questions', 1),
('Saved Articles', 2),
('Interesting Topics', 3),
('Important Notes', 1),
('To Review Later', 2),
('Must Read', 4),
('Follow Up', 3),
('Work Related', 2),
('Learning Resources', 5),
('Personal List', 1);
GO

INSERT INTO Question.Question (Title, [Description], AnswerId, SaveListId, UserId, CreateDate)
VALUES
('How to optimize SQL queries?', 'Looking for ways to speed up query execution in SQL.', NULL, 1, 1, '2024-09-01 14:35:00'),
('What is polymorphism in OOP?', 'Can someone explain the concept of polymorphism with examples?', NULL, 2, 2, '2024-09-05 09:22:00'),
('Best practices for REST API design?', 'What are the industry best practices for designing RESTful APIs?', NULL, 3, 3, '2024-09-10 11:15:00'),
('How to implement caching in .NET?', 'Need guidance on how to use caching in a .NET web application.', NULL, 1, 4, '2024-09-15 17:45:00'),
('What is a foreign key in databases?', 'Could anyone explain the purpose and function of foreign keys in relational databases?', NULL, 4, 2, '2024-09-18 13:05:00'),
('Difference between HTTP and HTTPS?', 'What are the main differences between HTTP and HTTPS protocols?', NULL, NULL, 5, '2024-09-20 08:30:00'),
('How to create stored procedures in SQL Server?', 'Looking for a step-by-step guide to creating stored procedures in SQL Server.', NULL, 2, 3, '2024-09-25 14:10:00'),
('What is agile methodology?', 'Could someone outline the principles and phases of agile methodology?', NULL, 5, 1, '2024-09-29 09:55:00'),
('How to manage state in React?', 'What are the different ways to manage state in a React application?', NULL, NULL, 4, '2024-10-01 16:40:00'),
('What is the SOLID principle in software development?', 'Can someone break down the SOLID principles for object-oriented design?', NULL, 1, 3, '2024-10-05 10:30:00');
GO

INSERT INTO Question.Answer ([Text], QuestionId, UserId, CreateDate)
VALUES
('You can use indexing and proper query planning to optimize SQL queries.', 1, 2, '2024-09-02 12:45:00'),
('Polymorphism allows objects to be treated as instances of their parent class.', 2, 1, '2024-09-06 10:05:00'),
('Design REST APIs using proper HTTP methods and status codes for each operation.', 3, 4, '2024-09-11 15:35:00'),
('In .NET, you can use memory caching or distributed caching solutions like Redis.', 4, 3, '2024-09-16 09:55:00'),
('A foreign key establishes a relationship between two tables, ensuring referential integrity.', 5, 2, '2024-09-19 12:25:00'),
('HTTPS is the secure version of HTTP that uses encryption for data transfer.', 6, 5, '2024-09-21 08:45:00'),
('You can create a stored procedure in SQL Server using the CREATE PROCEDURE statement.', 7, 1, '2024-09-26 11:10:00'),
('Agile methodology is iterative and focuses on delivering small, usable increments.', 8, 3, '2024-09-30 14:25:00'),
('State in React can be managed using hooks, Redux, or context API.', 9, 4, '2024-10-02 17:40:00'),
('The SOLID principles include Single Responsibility, Open/Closed, and others.', 10, 5, '2024-10-06 11:15:00'),
('You can optimize SQL by avoiding full table scans and using indexed columns.', 1, 3, '2024-09-03 14:20:00'),
('Polymorphism in OOP means methods can have the same name but act differently based on object type.', 2, 4, '2024-09-07 16:35:00'),
('Make sure to document your REST API endpoints and provide meaningful error messages.', 3, 5, '2024-09-12 10:00:00'),
('In .NET, you can implement caching by using the IMemoryCache interface for in-memory caching.', 4, 1, '2024-09-17 12:45:00'),
('Foreign keys ensure that data integrity is maintained across related tables.', 5, 3, '2024-09-20 10:25:00'),
('HTTPS uses SSL/TLS to encrypt data sent between the client and server.', 6, 2, '2024-09-22 09:00:00'),
('Stored procedures are precompiled, which improves performance for complex queries.', 7, 4, '2024-09-27 13:35:00'),
('Agile breaks down the development process into sprints, each focusing on a specific goal.', 8, 5, '2024-10-01 15:55:00'),
('React hooks like useState and useEffect are commonly used to manage state.', 9, 1, '2024-10-03 14:50:00'),
('The Single Responsibility Principle means that a class should have one and only one reason to change.', 10, 3, '2024-10-07 10:45:00'),
('Polymorphism allows for code flexibility and extensibility by treating subclasses as instances of their superclass.', 2, 3, '2024-09-04 09:30:00'),
('Make use of pagination and rate limiting when designing REST APIs for better performance.', 3, 1, '2024-09-08 11:15:00'),
('You can use Redis for distributed caching, especially in large-scale .NET applications.', 4, 5, '2024-09-13 13:40:00'),
('Foreign keys help maintain the consistency of relationships between data in different tables.', 5, 1, '2024-09-18 16:20:00'),
('HTTPS also provides identity verification, ensuring that users are communicating with the intended server.', 6, 4, '2024-09-23 14:00:00');
GO

INSERT INTO [User].Badge ([Name], RequiredRating)
VALUES
('SQL Master', 500),
('OOP Expert', 300),
('API Guru', 400),
('Caching Specialist', 250),
('Agile Practitioner', 150),
('React Pro', 350),
('Database Architect', 600),
('Security Savvy', 450),
('Performance Tuner', 550),
('Full Stack Developer', 500);
GO

INSERT INTO Question.Tag ([Name], EarnedRating)
VALUES
('SQL Optimization', 5),
('Polymorphism', 7),
('REST API', 6),
('.NET Caching', 4),
('Foreign Keys', 3),
('HTTPS', 2),
('Stored Procedures', 7),
('Agile Development', 9),
('React State Management', 8),
('SOLID Principles', 8);
GO

INSERT INTO Question.QuestionTag (QuestionId, TagId)
VALUES
(1, 1), -- SQL Optimization for "How to optimize SQL queries?"
(1, 4), -- .NET Caching for "How to optimize SQL queries?"
(2, 2), -- Polymorphism for "What is polymorphism in OOP?"
(2, 10), -- SOLID Principles for "What is polymorphism in OOP?"
(3, 3), -- REST API for "Best practices for REST API design?"
(3, 8), -- Agile Development for "Best practices for REST API design?"
(4, 4), -- .NET Caching for "How to implement caching in .NET?"
(4, 7), -- Stored Procedures for "How to implement caching in .NET?"
(5, 5), -- Foreign Keys for "What is a foreign key in databases?"
(5, 9), -- React State Management for "What is a foreign key in databases?"
(6, 6), -- HTTPS for "Difference between HTTP and HTTPS?"
(6, 8), -- Agile Development for "Difference between HTTP and HTTPS?"
(7, 7), -- Stored Procedures for "How to create stored procedures in SQL Server?"
(7, 1), -- SQL Optimization for "How to create stored procedures in SQL Server?"
(8, 8), -- Agile Development for "What is agile methodology?"
(8, 10), -- SOLID Principles for "What is agile methodology?"
(9, 9), -- React State Management for "How to manage state in React?"
(9, 2), -- Polymorphism for "How to manage state in React?"
(10, 10), -- SOLID Principles for "What is the SOLID principle in software development?"
(10, 1), -- SQL Optimization for "What is the SOLID principle in software development?"
(10, 4); -- .NET Caching for "What is the SOLID principle in software development?"
GO

------------ MAKE SOME ACTIONS TO CHECK IF ALL IS WORKING AS EXPECTED ------------
-- Update some questions with answered (set the answerId) and check if the users asked those question has their rating increased after that
EXEC [User].USP_GetUsersStatistics

UPDATE Question.Question SET AnswerId = 1 WHERE Id = 1
UPDATE Question.Question SET AnswerId = 8 WHERE Id = 8
UPDATE Question.Question SET AnswerId = 22 WHERE Id = 3
UPDATE Question.Question SET AnswerId = 7 WHERE Id = 7

EXEC [User].USP_GetUsersStatistics


SELECT * 
FROM [User].F_GetSavedLists(1)

-- Increase user ratings and check if they earn the badges for their new rating
EXEC [User].USP_GetUsersStatistics

UPDATE [User].[User]
SET Rating = Rating + Id * 50

EXEC [User].USP_GetUsersStatistics