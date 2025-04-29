### Data Masking Utility with Exclusion and Shuffling
This shell script automates sensitive data masking in MySQL databases. It supports email, phone, and generic column masking, and shuffles SSN/CSSN pairs while respecting an exclusion list.
##🔐 Features
- Masks sensitive columns based on pattern matching.
- Supports:
  - Email address masking (random@cloudtech.com)
  - Phone number randomly generating (9852545210)
  - Generic string masking (MASKED_XXXXXX)
- Skips masking based on values listed in an exclusion_list table.
- Shuffles SSN and CSSN values between rows, ensuring:
  - Excluded pairs are not changed.
  - Original SSN/CSSN pairs are not retained unless no alternatives exist.
- Automatically populates a lookup table to track columns and their masking status
