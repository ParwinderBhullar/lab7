# Lab 7 – Stored Procedures and Secure Dynamic SQL (DSL) Programming  
**Course:** SQL Server Development  
**Database:** AdventureWorks2022  
**Schema Used:** `Reporting`  

---

| Name | Student Number |
|------|----------------|
| [Parwinder Singh] | [N01730928] |

---

## Overview
This lab demonstrates how to build **secure, reusable, and idempotent stored procedures** in SQL Server, with a focus on preventing SQL injection attacks through **parameterized dynamic SQL** and **input validation**.

The work includes:
- Secure Dynamic SQL (DSL) implementation  
- Proper use of `sp_executesql`  
- Input validation and error handling  
- Output parameters and transaction control  
- Centralized execution logging for debugging and auditing  

All procedures are implemented within the `Reporting` schema in the **AdventureWorks2022** database.

---

## Stored Procedures and Their Purpose

| Procedure | Description | Key Features |
|------------|-------------|---------------|
| **`Reporting.GetSalesByTerritory`** | Retrieves total sales and order counts per territory. | Uses grouping and filtering by `@Territory`. |
| **`Reporting.DynamicSalesReport`** | Generates a flexible sales report filtered by territory, salesperson, or date range. | Secure dynamic SQL using `sp_executesql` with parameters and `TRY...CATCH` error logging. |
| **`Reporting.VulnerableProductSearch`** | Demonstrates insecure dynamic SQL vulnerable to injection. | Concatenates user input directly into SQL (for learning purpose only). |
| **`Reporting.SecureProductSearch`** | Secure version of product search using parameterized queries. | Prevents SQL injection through parameter binding and input validation. |
| **`Reporting.CheckInventoryLevel`** | Checks inventory quantity for a given product and returns stock status. | Uses logic and an output parameter to indicate status. |
| **`Reporting.SafeUpdateProductCost`** | Safely updates a product’s `ListPrice` using a transaction. | Includes rollback and logs errors to `Reporting.ExecutionLog`. |

---

## SQL Injection Prevention

SQL injection was prevented in this project by using secure dynamic SQL techniques directly in the stored procedures.

### How SQL Injection Was Prevented

- **Parameterized Dynamic SQL (`sp_executesql`)**  
  All procedures that use dynamic SQL (such as `Reporting.SecureProductSearch` and `Reporting.DynamicSalesReport`) rely on `sp_executesql` with parameters instead of concatenating user input into the SQL command.  
  This ensures SQL Server treats user input as data, not as executable code.  
  Example from the script:
  ```sql
  DECLARE @SQL NVARCHAR(MAX) = N'
      SELECT ProductID, Name
      FROM Production.Product
      WHERE Name LIKE @Pattern';

  DECLARE @Pattern NVARCHAR(102) = N'%' + @Category + N'%';

  EXEC sp_executesql
      @SQL,
      N'@Pattern NVARCHAR(102)',
      @Pattern;


