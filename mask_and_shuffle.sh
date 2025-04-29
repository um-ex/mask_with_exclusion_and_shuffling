#!/bin/bash
set -euo pipefail

# Masking generators
generate_random_email() {
    echo "$(tr -dc a-z0-9 </dev/urandom | head -c6)@cloudtech.com"
}

generate_random_phone() {
    echo "98$(tr -dc '0-9' </dev/urandom | head -c8)"
}

generate_random_generic() {
    echo "MASKED_$(tr -dc A-Z0-9 </dev/urandom | head -c6)"
}

# Escape single quotes in SQL values
escape_sql() {
    echo "$1" | sed "s/'/''/g"
}

# Function to shuffle CSSN4 and CSSN pairs
shuffle_cssn4_cssn_pairs() {
    local db="$1"
    local table="$2"
    local pk_col="$3"
    local exclusion_db="security_logs"
    local exclusion_table="exclusion_list"

    echo "Shuffling CSSN4/CSSN pairs for $db.$table"

    # Fetch all non-null CSSN4/CSSN pairs and primary keys
    data=$(sudo mysql --defaults-file=$HOME/.my.cnf -N -e "
        SELECT \`$pk_col\`, cssn4, cssn FROM \`$db\`.\`$table\`
        WHERE cssn4 IS NOT NULL OR cssn IS NOT NULL;
    ")

    declare -a ids
    declare -a original_pairs
    declare -a filtered_ids

    while IFS=$'\t' read -r pk cssn4 cssn; do
        # Escape for SQL
        cssn4_escaped=$(escape_sql "$cssn4")
        cssn_escaped=$(escape_sql "$cssn")

        # Skip if pair is in exclusion list
        exclusion_exists=0
        exclusion_exists=$(sudo mysql --defaults-file=$HOME/.my.cnf -N -e "
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = '$exclusion_db' AND table_name = '$exclusion_table';
        ")

        if [[ "$exclusion_exists" -gt 0 ]]; then
            is_excluded=$(sudo mysql --defaults-file=$HOME/.my.cnf -N -e "
                SELECT COUNT(*) FROM \`$exclusion_db\`.\`$exclusion_table\`
                WHERE cssn4 = '$cssn4_escaped' AND cssn = '$cssn_escaped';
            ")
            if [[ "$is_excluded" -gt 0 ]]; then
                echo "Skipping shuffle for CSSN4: $cssn4 and CSSN: $cssn (in exclusion list)"
                continue
            fi
        fi

        original_pairs+=("$cssn4,$cssn")
        ids+=("$pk")
    done <<< "$data"

    # If not enough to shuffle, skip
    if [[ "${#original_pairs[@]}" -lt 2 ]]; then
        echo "Not enough records to shuffle."
        return
    fi

    # Shuffle
    shuffled_pairs=($(printf "%s\n" "${original_pairs[@]}" | shuf))

    # Ensure no row receives its original pair
    for ((i = 0; i < ${#ids[@]}; i++)); do
        original="${original_pairs[$i]}"
        new="${shuffled_pairs[$i]}"
        attempts=0

        # Retry up to 5 times to avoid original match
        while [[ "$original" == "$new" && $attempts -lt 5 ]]; do
            rand_idx=$((RANDOM % ${#shuffled_pairs[@]}))
            temp="${shuffled_pairs[$rand_idx]}"
            shuffled_pairs[$rand_idx]="$new"
            new="$temp"
            attempts=$((attempts + 1))
        done

        if [[ "$original" == "$new" ]]; then
            echo "Skipping ID ${ids[$i]} to avoid original CSSN4/CSSN reuse"
            continue
        fi

        IFS=',' read -r new_cssn4 new_cssn <<< "$new"
        pk_escaped=$(escape_sql "${ids[$i]}")
        new_cssn4_escaped=$(escape_sql "$new_cssn4")
        new_cssn_escaped=$(escape_sql "$new_cssn")

        sudo mysql --defaults-file=$HOME/.my.cnf -e "
            UPDATE \`$db\`.\`$table\`
            SET cssn4 = '$new_cssn4_escaped', cssn = '$new_cssn_escaped'
            WHERE \`$pk_col\` = '$pk_escaped';
        "
    done

    echo "Finished shuffling CSSN4/CSSN pairs for $db.$table"
}

# Generator selector
get_masking_function() {
    col_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    if [[ "$col_lower" == "cssn4" || "$col_lower" == "cssn" ]]; then
        echo "skip"
    elif [[ $col_lower == *email* ]]; then
        echo "generate_random_email"
    elif [[ $col_lower == *phone* || $col_lower == *mobile* ]]; then
        echo "generate_random_phone"
    else
        echo "generate_random_generic"
    fi
}

# Begin masking
LOOKUP_DB="security_logs"
LOOKUP_TABLE="lookup"
EXCLUSION_TABLE="exclusion_list"

rows=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
SELECT database_name, table_name, column_name
FROM \`$LOOKUP_DB\`.\`$LOOKUP_TABLE\`
WHERE to_mask = 1 AND primary_key = 0;
")

declare -A tables_to_shuffle

while IFS=$'\t' read -r db table col; do
    echo "Masking $db.$table.$col"

    if [[ "$col" == "cssn4" || "$col" == "cssn" ]]; then
        tables_to_shuffle["$db.$table"]=1
        continue
    fi

    func_name=$(get_masking_function "$col")
    [[ "$func_name" == "skip" ]] && continue

    pk_col=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$db' AND table_name = '$table' AND column_key = 'PRI'
        LIMIT 1;
    ")

    if [[ -z "$pk_col" ]]; then
        echo "No primary key for $db.$table. Skipping..."
        continue
    fi

    ids=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
        SELECT \`$pk_col\` FROM \`$db\`.\`$table\`;
    ")

    # Check if exclusion table exists and has column
    table_exists=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = '$LOOKUP_DB' AND table_name = '$EXCLUSION_TABLE';
    ")

    column_exists=0
    if [[ "$table_exists" -eq 1 ]]; then
        column_exists=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
            SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = '$LOOKUP_DB' AND table_name = '$EXCLUSION_TABLE' AND column_name COLLATE utf8_general_ci = '$col';
        ")
    fi

    exclusions=""
    if [[ "$column_exists" -eq 1 ]]; then
        exclusions=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
            SELECT \`$col\` FROM \`$LOOKUP_DB\`.\`$EXCLUSION_TABLE\` WHERE \`$col\` IS NOT NULL;
        ")
    fi

    for id in $ids; do
        current_val=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
            SELECT \`$col\` FROM \`$db\`.\`$table\` WHERE \`$pk_col\` = '$id' LIMIT 1;
        ")

        skip=0
        if [[ -n "$exclusions" ]]; then
            while IFS= read -r exclude_val; do
                if [[ "$current_val" == "$exclude_val" ]]; then
                    skip=1
                    break
                fi
            done <<< "$exclusions"
        fi

        if [[ "$skip" -eq 1 ]]; then
            echo "Skipping $db.$table.$col for ID $id (excluded)"
            continue
        fi

        new_val=$($func_name)
        max_len=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
            SELECT CHARACTER_MAXIMUM_LENGTH
            FROM information_schema.columns
            WHERE table_schema = '$db' AND table_name = '$table' AND column_name = '$col';
        ")

        if [[ "$max_len" =~ ^[0-9]+$ ]]; then
            new_val=$(echo "$new_val" | cut -c1-"$max_len")
        fi

        new_val_escaped=$(escape_sql "$new_val")

        sudo mysql --defaults-file="$HOME/.my.cnf" -e "
            UPDATE \`$db\`.\`$table\`
            SET \`$col\` = '$new_val_escaped'
            WHERE \`$pk_col\` = '$id';
        "
    done
done <<< "$rows"

# Shuffle CSSN4/CSSN fields
for db_table in "${!tables_to_shuffle[@]}"; do
    db="${db_table%%.*}"
    table="${db_table#*.}"

    pk_col=$(sudo mysql --defaults-file="$HOME/.my.cnf" -N -e "
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '$db' AND table_name = '$table' AND column_key = 'PRI'
        LIMIT 1;
    ")

    if [[ -n "$pk_col" ]]; then
        shuffle_cssn4_cssn_pairs "$db" "$table" "$pk_col"
    fi
done

echo "All sensitive fields masked. CSSN4/CSSN pairs shuffled."
