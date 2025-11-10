/********************************************************************************************
   LAB 7 IMPLEMENTATION SCRIPT
   Course: SQL Server Development
   Title: Stored Procedures and Secure Dynamic SQL (DSL) Programming
   Database: AdventureWorks2022
********************************************************************************************/

USE AdventureWorks2022;
GO

/*==============================================================
  1. SCHEMA AND LOGGING TABLE CREATION
==============================================================*/
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Reporting')
    EXEC('CREATE SCHEMA Reporting AUTHORIZATION dbo;');
GO

IF OBJECT_ID('Reporting.ExecutionLog', 'U') IS NOT NULL
    DROP TABLE Reporting.ExecutionLog;
GO

CREATE TABLE Reporting.ExecutionLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    ProcedureName NVARCHAR(100),
    ExecutedSQL NVARCHAR(MAX),
    ExecutionDate DATETIME DEFAULT GETDATE(),
    ErrorMessage NVARCHAR(4000)
);
GO


/*==============================================================
  2. STORED PROCEDURE – GetSalesByTerritory
==============================================================*/
IF OBJECT_ID('Reporting.GetSalesByTerritory', 'P') IS NOT NULL
    DROP PROCEDURE Reporting.GetSalesByTerritory;
GO

CREATE PROCEDURE Reporting.GetSalesByTerritory
    @Territory NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.Name AS Territory,
        COUNT(DISTINCT s.SalesOrderID) AS OrdersCount,
        SUM(s.SubTotal) AS TotalSales
    FROM Sales.SalesOrderHeader s
    INNER JOIN Sales.SalesTerritory t ON s.TerritoryID = t.TerritoryID
    WHERE t.Name = @Territory
    GROUP BY t.Name;
END;
GO

-- TEST
EXEC Reporting.GetSalesByTerritory @Territory = 'Northwest';
GO


/*==============================================================
  3. STORED PROCEDURE – DynamicSalesReport (Secure DSL)
==============================================================*/
IF OBJECT_ID('Reporting.DynamicSalesReport', 'P') IS NOT NULL
    DROP PROCEDURE Reporting.DynamicSalesReport;
GO

CREATE PROCEDURE Reporting.DynamicSalesReport
    @Territory NVARCHAR(50) = NULL,
    @SalesPerson NVARCHAR(100) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT 
            t.Name AS Territory,
            p.FirstName + '' '' + p.LastName AS SalesPerson,
            SUM(s.SubTotal) AS TotalSales
        FROM Sales.SalesOrderHeader s
        INNER JOIN Sales.SalesTerritory t ON s.TerritoryID = t.TerritoryID
        INNER JOIN Sales.SalesPerson sp ON s.SalesPersonID = sp.BusinessEntityID
        INNER JOIN Person.Person p ON sp.BusinessEntityID = p.BusinessEntityID
        WHERE 1=1';

    IF @Territory IS NOT NULL SET @SQL += N' AND t.Name = @Territory';
    IF @SalesPerson IS NOT NULL SET @SQL += N' AND (p.FirstName + '' '' + p.LastName) = @SalesPerson';
    IF @StartDate IS NOT NULL SET @SQL += N' AND s.OrderDate >= @StartDate';
    IF @EndDate IS NOT NULL SET @SQL += N' AND s.OrderDate <= @EndDate';

    SET @SQL += N' GROUP BY t.Name, p.FirstName, p.LastName ORDER BY TotalSales DESC';

    BEGIN TRY
        EXEC sp_executesql
            @SQL,
            N'@Territory NVARCHAR(50), @SalesPerson NVARCHAR(100), @StartDate DATE, @EndDate DATE',
            @Territory, @SalesPerson, @StartDate, @EndDate;
    END TRY
    BEGIN CATCH
        INSERT INTO Reporting.ExecutionLog (ProcedureName, ExecutedSQL, ErrorMessage)
        VALUES ('Reporting.DynamicSalesReport', @SQL, ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- TESTS
EXEC Reporting.DynamicSalesReport @Territory = 'Northwest';
EXEC Reporting.DynamicSalesReport @SalesPerson = 'David Campbell';
EXEC Reporting.DynamicSalesReport @StartDate = '2022-01-01', @EndDate = '2022-12-31';
GO


/*==============================================================
  4. STORED PROCEDURES – Vulnerable vs Secure Dynamic SQL
==============================================================*/
IF OBJECT_ID('Reporting.VulnerableProductSearch', 'P') IS NOT NULL
    DROP PROCEDURE Reporting.VulnerableProductSearch;
GO

CREATE PROCEDURE Reporting.VulnerableProductSearch
    @Category NVARCHAR(100)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX) = N'
        SELECT ProductID, Name 
        FROM Production.Product
        WHERE Name LIKE ''%' + @Category + '%''';
    EXEC(@SQL);
END;
GO

IF OBJECT_ID('Reporting.SecureProductSearch', 'P') IS NOT NULL
    DROP PROCEDURE Reporting.SecureProductSearch;
GO

CREATE PROCEDURE Reporting.SecureProductSearch
    @Category NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    -- Normalize input
    SET @Category = LTRIM(RTRIM(@Category));

    -- Validate input: prevent empty or NULL filters
    IF @Category IS NULL OR @Category = ''
    BEGIN
        RAISERROR('Category filter cannot be empty. Please provide a valid value.', 16, 1);
        RETURN;
    END;

    DECLARE 
        @SQL NVARCHAR(MAX) = N'
            SELECT ProductID, Name 
            FROM Production.Product
            WHERE Name LIKE @Pattern',
        @Pattern NVARCHAR(102);

    SET @Pattern = N'%' + @Category + N'%';

    BEGIN TRY
        EXEC sp_executesql 
            @SQL,
            N'@Pattern NVARCHAR(102)',
            @Pattern = @Pattern;
    END TRY
    BEGIN CATCH
        PRINT 'Error: ' + ERROR_MESSAGE();
    END CATCH;
END;
GO


-- TESTS
EXEC Reporting.VulnerableProductSearch @Category = 'Road';
EXEC Reporting.SecureProductSearch @Category = 'Mountain';

EXEC Reporting.SecureProductSearch @Category = '';
GO


/*==============================================================
  5. STORED PROCEDURE – CheckInventoryLevel (OUT Parameter)
==============================================================*/
IF OBJECT_ID('Reporting.CheckInventoryLevel', 'P') IS NOT NULL
    DROP PROCEDURE Reporting.CheckInventoryLevel;
GO

CREATE PROCEDURE Reporting.CheckInventoryLevel
    @ProductID INT,
    @Status NVARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Qty INT;
    SELECT @Qty = SUM(Quantity)
    FROM Production.ProductInventory
    WHERE ProductID = @ProductID;

    IF @Qty IS NULL
        SET @Status = 'Unknown';
    ELSE IF @Qty < 50
        SET @Status = 'Low';
    ELSE
        SET @Status = 'Sufficient';
END;
GO

-- TEST
DECLARE @InventoryStatus NVARCHAR(20);
EXEC Reporting.CheckInventoryLevel @ProductID = 776, @Status = @InventoryStatus OUTPUT;
PRINT 'Inventory Status: ' + @InventoryStatus;
GO


/*==============================================================
  6. STORED PROCEDURE – SafeUpdateProductCost (TRY...CATCH)
==============================================================*/
IF OBJECT_ID('Reporting.SafeUpdateProductCost', 'P') IS NOT NULL
    DROP PROCEDURE Reporting.SafeUpdateProductCost;
GO

CREATE PROCEDURE Reporting.SafeUpdateProductCost
    @ProductID INT,
    @NewListPrice MONEY
AS
BEGIN
    BEGIN TRAN;

    BEGIN TRY
        UPDATE Production.Product
        SET ListPrice = @NewListPrice
        WHERE ProductID = @ProductID;

        IF @@ROWCOUNT = 0
            THROW 51000, 'Product not found', 1;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRAN;
        INSERT INTO Reporting.ExecutionLog (ProcedureName, ExecutedSQL, ErrorMessage)
        VALUES ('Reporting.SafeUpdateProductCost', 'UPDATE Production.Product...', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- TESTS
EXEC Reporting.SafeUpdateProductCost @ProductID = 680, @NewListPrice = 2100.00; -- valid
EXEC Reporting.SafeUpdateProductCost @ProductID = 999999, @NewListPrice = 2000.00; -- invalid to trigger log
GO


/*==============================================================
  7. VALIDATION AND LOG REVIEW
==============================================================*/
SELECT * FROM Reporting.ExecutionLog ORDER BY ExecutionDate DESC;
GO
