/* =====================================================================
   EMPLOYEE PERFORMANCE DASHBOARD  —  SQL SERVER (T-SQL) VERSION
   Dataset : HRDataset_v14.csv (311 employees, real Salary column)

   NOTE: No CREATE TABLE here since you're importing the CSV directly
   via SQL Server's Import Wizard / bulk insert. All queries below
   assume the imported table is called [employees].

   >>> If your imported table has a different name (e.g. HRDataset_v14,
       dbo.HR_Data, etc.), do a find-and-replace of "employees" with
       your actual table name before running.

   Also double-check these two things after import, since the wizard
   sometimes gets them wrong:
   1. Salary should import as INT or DECIMAL, not VARCHAR/NVARCHAR
      (if it comes in as text, window function math will still work,
      but ORDER BY will sort alphabetically, not numerically — cast it:
      CAST(Salary AS INT))
   2. DateofHire / DateofTermination / LastPerformanceReview_Date should
      import as DATE or DATETIME, not text — if they come in as
      VARCHAR (e.g. "7/5/2011"), use:
      CONVERT(DATE, DateofHire, 101)  -- style 101 = mm/dd/yyyy
   ===================================================================== */


/* ---------------------------------------------------------------------
   1. RANK EMPLOYEES WITHIN EACH DEPARTMENT BY SALARY
   --------------------------------------------------------------------- */
SELECT
    Department,
    Employee_Name,
    Salary,
    RANK()       OVER (PARTITION BY Department ORDER BY Salary DESC) AS salary_rank,
    DENSE_RANK() OVER (PARTITION BY Department ORDER BY Salary DESC) AS salary_dense_rank,
    ROW_NUMBER() OVER (PARTITION BY Department ORDER BY Salary DESC) AS salary_row_num
FROM employees
WHERE EmploymentStatus = 'Active'
ORDER BY Department, salary_rank;


/* ---------------------------------------------------------------------
   2. DEPARTMENT AVERAGE SALARY vs. EACH EMPLOYEE
   --------------------------------------------------------------------- */

SELECT
    Department,
    Employee_Name,
    Salary,
    ROUND(AVG(Salary) OVER (PARTITION BY Department), 2) AS dept_avg_salary,
    ROUND(Salary - AVG(Salary) OVER (PARTITION BY Department), 2) AS diff_from_dept_avg,
    ROUND(
        100.0 * (Salary - AVG(Salary) OVER (PARTITION BY Department))
        / AVG(Salary) OVER (PARTITION BY Department), 1
    ) AS pct_diff_from_dept_avg
FROM employees
WHERE EmploymentStatus = 'Active'
ORDER BY Department, diff_from_dept_avg DESC;


/* ---------------------------------------------------------------------
   3. TOP 10% OF EARNERS, COMPANY-WIDE
   --------------------------------------------------------------------- */

WITH salary_deciles AS (
    SELECT
        Employee_Name,
        Department,
        Position,
        Salary,
        NTILE(10) OVER (ORDER BY Salary DESC) AS salary_decile
    FROM employees
    WHERE EmploymentStatus = 'Active'
)
SELECT *
FROM salary_deciles
WHERE salary_decile = 1
ORDER BY Salary DESC;


/* ---------------------------------------------------------------------
   4. ATTRITION RATE BY JOB ROLE AND DEPARTMENT
   --------------------------------------------------------------------- */

SELECT
    Department,
    Position,
    COUNT(*) AS headcount_ever,
    SUM(CASE WHEN EmploymentStatus NOT IN ('Active', 'Leave of Absence')
             THEN 1 ELSE 0 END) AS terminated_count,
    ROUND(
        100.0 * SUM(CASE WHEN EmploymentStatus NOT IN ('Active', 'Leave of Absence')
                          THEN 1 ELSE 0 END) / COUNT(*), 1
    ) AS attrition_rate_pct
FROM employees
GROUP BY Department, Position
HAVING COUNT(*) >= 3          -- drop noisy 1-2 person roles; remove filter to see everything
ORDER BY attrition_rate_pct DESC;

-- Department-level roll-up:
SELECT
    Department,
    COUNT(*) AS headcount_ever,
    SUM(CASE WHEN EmploymentStatus NOT IN ('Active', 'Leave of Absence')
             THEN 1 ELSE 0 END) AS terminated_count,
    ROUND(
        100.0 * SUM(CASE WHEN EmploymentStatus NOT IN ('Active', 'Leave of Absence')
                          THEN 1 ELSE 0 END) / COUNT(*), 1
    ) AS attrition_rate_pct
FROM employees
GROUP BY Department
ORDER BY attrition_rate_pct DESC;


/* ---------------------------------------------------------------------
   5. LONG-TENURED EMPLOYEES WITHOUT A ROLE CHANGE (>5 years, same title)
   The dataset has no promotion-history table, so "same role" is proxied
   by (a) still active and (b) tenure in the current Position derived
   from DateofHire. Call this assumption out if you present the metric.
   --------------------------------------------------------------------- */

SELECT
    Employee_Name,
    Department,
    Position,
    DateofHire,
    DATEDIFF(YEAR, DateofHire, GETDATE())
        - CASE WHEN (MONTH(GETDATE()) < MONTH(DateofHire))
                 OR (MONTH(GETDATE()) = MONTH(DateofHire) AND DAY(GETDATE()) < DAY(DateofHire))
               THEN 1 ELSE 0 END AS years_in_role
FROM employees
WHERE EmploymentStatus = 'Active'
  AND DATEDIFF(YEAR, DateofHire, GETDATE())
      - CASE WHEN (MONTH(GETDATE()) < MONTH(DateofHire))
               OR (MONTH(GETDATE()) = MONTH(DateofHire) AND DAY(GETDATE()) < DAY(DateofHire))
             THEN 1 ELSE 0 END > 5
ORDER BY years_in_role DESC;

-- Simpler version if exact year-boundary precision doesn't matter to you
-- (DATEDIFF(YEAR,...) counts calendar-year crossings, not full 365-day
-- years, so it can be off by up to 1 year near a hire-date anniversary):
-- SELECT Employee_Name, Department, Position, DateofHire,
--        DATEDIFF(YEAR, DateofHire, GETDATE()) AS years_in_role
-- FROM employees
-- WHERE EmploymentStatus = 'Active'
--   AND DATEDIFF(YEAR, DateofHire, GETDATE()) > 5;


/* =====================================================================
   STRETCH GOAL: SALARY BAND ANALYSIS (QUARTILES PER DEPARTMENT)
   ===================================================================== */

WITH quartiles AS (
    SELECT
        Department,
        Employee_Name,
        Position,
        Salary,
        NTILE(4) OVER (PARTITION BY Department ORDER BY Salary) AS salary_quartile
    FROM employees
    WHERE EmploymentStatus = 'Active'
)
SELECT
    Department,
    Employee_Name,
    Position,
    Salary,
    salary_quartile,
    CASE salary_quartile
        WHEN 1 THEN 'Bottom 25%'
        WHEN 2 THEN 'Lower Mid'
        WHEN 3 THEN 'Upper Mid'
        WHEN 4 THEN 'Top 25%'
    END AS salary_band
FROM quartiles
ORDER BY Department, salary_quartile, Salary;

-- Summary view: min/max/avg salary per band per department, useful for
-- a compensation-team style pay-band table.
WITH quartiles AS (
    SELECT
        Department,
        Salary,
        NTILE(4) OVER (PARTITION BY Department ORDER BY Salary) AS salary_quartile
    FROM employees
    WHERE EmploymentStatus = 'Active'
)
SELECT
    Department,
    salary_quartile,
    CASE salary_quartile
        WHEN 1 THEN 'Bottom 25%'
        WHEN 2 THEN 'Lower Mid'
        WHEN 3 THEN 'Upper Mid'
        WHEN 4 THEN 'Top 25%'
    END AS salary_band,
    COUNT(*)             AS headcount,
    MIN(Salary)          AS band_min,
    MAX(Salary)          AS band_max,
    ROUND(AVG(Salary),2) AS band_avg
FROM quartiles
GROUP BY Department, salary_quartile
ORDER BY Department, salary_quartile;


/* =====================================================================
   BONUS: OUTLIER DETECTION (z-score, >2 std devs from department mean)
   T-SQL uses STDEV (one D), not STDDEV.
   ===================================================================== */

WITH dept_stats AS (
    SELECT
        Department,
        Employee_Name,
        Salary,
        AVG(Salary)   OVER (PARTITION BY Department) AS dept_avg,
        STDEV(Salary) OVER (PARTITION BY Department) AS dept_stdev
    FROM employees
    WHERE EmploymentStatus = 'Active'
)
SELECT
    Department,
    Employee_Name,
    Salary,
    ROUND(dept_avg, 2) AS dept_avg_salary,
    ROUND(dept_stdev, 2) AS dept_stdev,
    ROUND((Salary - dept_avg) / NULLIF(dept_stdev, 0), 2) AS z_score,
    CASE WHEN ABS((Salary - dept_avg) / NULLIF(dept_stdev, 0)) > 2
         THEN 'Outlier' ELSE 'Normal' END AS outlier_flag
FROM dept_stats
ORDER BY ABS((Salary - dept_avg) / NULLIF(dept_stdev, 0)) DESC;
