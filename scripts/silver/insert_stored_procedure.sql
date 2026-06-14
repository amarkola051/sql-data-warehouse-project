CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
BEGIN
    ---------------------------------------------------------------------------
    -- 1. LOAD: silver.crm_cust_info
    ---------------------------------------------------------------------------
    BEGIN
        RAISE NOTICE 'Truncating table: silver.crm_cust_info';
        TRUNCATE TABLE silver.crm_cust_info;

        RAISE NOTICE 'Inserting data into: silver.crm_cust_info';
        INSERT INTO silver.crm_cust_info (
            cst_id, cst_key, cst_firstname, cst_lastname, 
            cst_marital_status, cst_gndr, cst_create_date
        )
        SELECT 
            cst_id, cst_key, TRIM(cst_firstname), TRIM(cst_lastname),
            CASE 
                WHEN TRIM(UPPER(cst_marital_status)) = 'S' THEN 'Single'
                WHEN TRIM(UPPER(cst_marital_status)) = 'M' THEN 'Married'
                ELSE 'n/a'
            END,
            CASE 
                WHEN TRIM(UPPER(cst_gndr)) = 'M' THEN 'Male'
                WHEN TRIM(UPPER(cst_gndr)) = 'F' THEN 'Female'
                ELSE 'n/a'
            END,
            cst_create_date
        FROM (
            SELECT *, 
                   ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
            FROM bronze.crm_cust_info
        ) t 
        WHERE flag_last = 1;

        COMMIT; 
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE WARNING 'CRITICAL ERROR in silver.crm_cust_info: %. Moving to next table.', SQLERRM;
    END;


    ---------------------------------------------------------------------------
    -- 2. LOAD: silver.crm_prd_info
    ---------------------------------------------------------------------------
    BEGIN
        RAISE NOTICE 'Truncating table: silver.crm_prd_info';
        TRUNCATE TABLE silver.crm_prd_info;

        RAISE NOTICE 'Inserting data into: silver.crm_prd_info';
        INSERT INTO silver.crm_prd_info (
            prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt
        )
        SELECT
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_'),
            SUBSTRING(prd_key, 7, LENGTH(prd_key)),
            prd_nm,
            COALESCE(prd_cost, 0),
            CASE UPPER(TRIM(prd_line)) 
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'other sales'
                ELSE 'n/a'
            END,
            prd_start_dt::DATE,
            (LEAD(prd_start_dt) OVER(PARTITION BY prd_key ORDER BY prd_start_dt)::DATE) - 1
        FROM bronze.crm_prd_info;

        COMMIT;
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE WARNING 'CRITICAL ERROR in silver.crm_prd_info: %. Moving to next table.', SQLERRM;
    END;


    ---------------------------------------------------------------------------
    -- 3. LOAD: silver.crm_sales_details
    ---------------------------------------------------------------------------
    BEGIN
        RAISE NOTICE 'Truncating table: silver.crm_sales_details';
        TRUNCATE TABLE silver.crm_sales_details;

        RAISE NOTICE 'Inserting data into: silver.crm_sales_details';
        INSERT INTO silver.crm_sales_details (
            sls_ord_num, sls_prd_key, sls_cust_id, sls_order_dt, 
            sls_ship_dt, sls_due_dt, sls_sales, sls_quantity, sls_price
        )
        SELECT
            sls_ord_num, sls_prd_key, sls_cust_id,
            CASE 
                WHEN sls_order_dt = 0 OR LENGTH(sls_order_dt::VARCHAR) <> 8 THEN NULL 
                ELSE (sls_order_dt::VARCHAR)::DATE 
            END,
            CASE 
                WHEN sls_ship_dt = 0 OR LENGTH(sls_ship_dt::VARCHAR) <> 8 THEN NULL 
                ELSE (sls_ship_dt::VARCHAR)::DATE 
            END,
            CASE 
                WHEN sls_due_dt = 0 OR LENGTH(sls_due_dt::VARCHAR) <> 8 THEN NULL 
                ELSE (sls_due_dt::VARCHAR)::DATE 
            END,
            CASE 
                WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
                    THEN sls_quantity * ABS(sls_price) 
                ELSE sls_sales 
            END,
            sls_quantity,
            CASE 
                WHEN sls_price IS NULL OR sls_price <= 0
                    THEN sls_sales / NULLIF(sls_quantity, 0) 
                ELSE prs_price 
            END
        FROM bronze.crm_sales_details;

        COMMIT; 
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE WARNING 'CRITICAL ERROR in silver.crm_sales_details: %. Moving to next table.', SQLERRM;
    END;


    ---------------------------------------------------------------------------
    -- 4. LOAD: silver.erp_cust_az12
    ---------------------------------------------------------------------------
    BEGIN
        RAISE NOTICE 'Truncating table: silver.erp_cust_az12';
        TRUNCATE TABLE silver.erp_cust_az12;

        RAISE NOTICE 'Inserting data into: silver.erp_cust_az12';
        INSERT INTO silver.erp_cust_az12 (cid, bdate, gen)
        SELECT
            CASE 
                WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LENGTH(cid))
                ELSE cid
            END,
            CASE 
                WHEN bdate > CURRENT_DATE THEN NULL
                ELSE bdate 
            END,
            CASE 
                WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
                WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
                ELSE 'n/a' 
            END
        FROM bronze.erp_cust_az12;

        COMMIT;
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE WARNING 'CRITICAL ERROR in silver.erp_cust_az12: %. Moving to next table.', SQLERRM;
    END;


    ---------------------------------------------------------------------------
    -- 5. LOAD: silver.erp_loc_a101
    ---------------------------------------------------------------------------
    BEGIN
        RAISE NOTICE 'Truncating table: silver.erp_loc_a101';
        TRUNCATE TABLE silver.erp_loc_a101;

        RAISE NOTICE 'Inserting data into: silver.erp_loc_a101';
        INSERT INTO silver.erp_loc_a101 (cid, cntry)
        SELECT 
            REPLACE(cid, '-', ''),
            CASE 
                WHEN UPPER(TRIM(cntry)) IN ('US', 'USA') THEN 'United States'
                WHEN UPPER(TRIM(cntry)) = 'DE' THEN 'Germany'
                WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a' 
                ELSE TRIM(cntry) -- Added missing ELSE rule
            END
        FROM bronze.erp_loc_a101;

        COMMIT; 
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE WARNING 'CRITICAL ERROR in silver.erp_loc_a101: %. Moving to next table.', SQLERRM;
    END;


    ---------------------------------------------------------------------------
    -- 6. LOAD: silver.erp_px_cat_g1v2
    ---------------------------------------------------------------------------
    BEGIN
        RAISE NOTICE 'Truncating table: silver.erp_px_cat_g1v2';
        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        RAISE NOTICE 'Inserting data into: silver.erp_px_cat_g1v2';
        INSERT INTO silver.erp_px_cat_g1v2 (id, cat, subcat, maintenance)
        SELECT id, cat, subcat, maintenance
        FROM bronze.erp_px_cat_g1v2;

        COMMIT; 
    EXCEPTION 
        WHEN OTHERS THEN
            RAISE WARNING 'CRITICAL ERROR in silver.erp_px_cat_g1v2: %. Batch finish warning.', SQLERRM;
    END;

    RAISE NOTICE 'Silver layer pipeline completed.';
END;
$$;
