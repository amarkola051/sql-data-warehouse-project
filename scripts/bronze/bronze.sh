#!/bin/bash

set -e

# Database Configuration
DB_NAME="datawarehouse"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5432"
export PGPASSWORD="*******"

# directories

CRM_DIR="/home/amar-kola/Documents/datasets/source_crm"
ERP_DIR="/home/amar-kola/Documents/datasets/source_erp"

load_table(){
local table=$1
local file=$2

echo ">> Truncating Table: $table"
PGPASSWORD="Amar@0331" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "TRUNCATE TABLE $table;"
echo ">> Inserting Data Into: $table"

local start_time=$(date +%s)
PGPASSWORD="Amar@0331" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
        "\copy $table FROM '$file' WITH DELIMITER ',' CSV HEADER;"
local end_time=$(date +%s)
local duration=$((end_time - start_time))

echo ">> Load duration: $duration seconds"
echo ">>-------------------------------------"
}
# error handling

failure_handler(){
echo "======================================="
echo "ERROR OCCURRED DURING LOADING BRONZE LAYER"
echo "Check file paths, table definitions, or DB connectivity."
echo "======================================="
exit 1
}

trap "failure_handler" ERR

# MAIN EXECUTION

batch_start_time=$(date +%s)

echo "====================================="
echo "Loading Bronze Layer"
echo "====================================="

# --- CRM TABLES ---

echo "-------------------------------------"
echo "Loading CRM Tables"
echo "-------------------------------------"

load_table "bronze.crm_cust_info"     "$CRM_DIR/cust_info.csv"
load_table "bronze.crm_prd_info"      "$CRM_DIR/prd_info.csv"
load_table "bronze.crm_sales_details" "$CRM_DIR/sales_details.csv"

# --- ERP TABLES ---
echo "-------------------------------------"
echo "Loading ERP Tables"
echo "-------------------------------------"

load_table "bronze.erp_loc_a101"     "$ERP_DIR/LOC_A101.csv"
load_table "bronze.erp_cust_az12"     "$ERP_DIR/CUST_AZ12.csv"
load_table "bronze.erp_px_cat_g1v2"   "$ERP_DIR/PX_CAT_G1V2.csv"


batch_end_time=$(date +%s)
total_duration=$((batch_end_time - batch_start_time))

echo "=========================================="
echo "Loading Bronze Layer is Completed"
echo "   - Total Load Duration: $total_duration seconds"
echo "=========================================="

