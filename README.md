### Data Masking Utility with Exclusion and Shuffling
This shell script automates sensitive data masking in MySQL databases. It supports email, phone, and generic column masking, and shuffles SSN/CSSN pairs while respecting an exclusion list.  
## 🔐 Features
- Masks sensitive columns based on pattern matching.
- Supports:
  - Email address masking (random@gmail.com)
  - Phone number randomly generating (9852545210)
  - Generic string masking (MASKED_XXXXXX)
- Skips masking based on values listed in an exclusion_list table.
- Shuffles SSN and CSSN values between rows, ensuring:
  - Excluded pairs are not changed.
  - Original SSN/CSSN pairs are not retained unless no alternatives exist.
- Automatically populates a lookup table to track columns and their masking status

## 📁 Project Structure 
```bash
.
├── generate_lookup.sh     # Creates lookup table with maskable fields
├── mask_and_shuffle.sh    # Applies masking and SSN/CSSN shuffling
├── README.md              # This file

```
## 🧰 Requirements
- MySQL client installed (mysql)
- .my.cnf file in your home directory for authentication
- Bash environment (Linux/macOS/WSL)

## ⚙️ Setup
1. Prepare .my.cnf
Ensure you have a .my.cnf file in your home directory with the following: 
```bash
[client]
host=your_host_name
user=your_mysql_user
password=your_mysql_password

```

2. Create Exclusion List Table 
In your security_logs database:
```bash
CREATE TABLE IF NOT EXISTS security_logs.exclusion_list (
    email VARCHAR(255),
    phone VARCHAR(20),
    ssn VARCHAR(20),
    cssn VARCHAR(20)
);

```
Populate it with values you want excluded from masking/shuffling.

## 🚀 Usage
1. Generate Lookup Table
```bash
chmod +x create_lookup.sh
./create_lookup.sh
```
This scans all non-system databases, identifies sensitive columns, and logs them in security_logs.lookup 

2. Mask and Shuffle Data
```bash
chmod +x mask_and_shuffle.sh
./mask_and_shuffle.sh
```
This script:
- Masks columns marked as sensitive.
- Shuffles SSN/CSSN pairs while skipping those in the exclusion list.  
## 📋 Notes
- The generate_lookup.sh script recreates the lookup table but preserves the exclusion_list.
- The lookup table must exist and be populated before running the masking script.
- Columns with primary keys are automatically excluded from masking.