# Lists every table, column, sequence, index and named constraint that
# src/tables/install.sql creates, one "KIND|NAME" line each. A column is
# "TABLE.COLUMN". generate_upgrade_script.sh turns the list into the verify
# phase of upgrade_uc_ai.sql.
#
# It reads the layout of install.sql: "create table x (" on its own line, one
# column per line indented by two spaces, and the closing ")" in column 1.

{
  line = tolower($0)
  sub(/--.*/, "", line)
}

line ~ /^create table / {
  table_name = line
  sub(/^create table +/, "", table_name)
  sub(/[ (].*/, "", table_name)
  print "TABLE|" toupper(table_name)
  in_table = 1
  next
}

in_table && line ~ /^\)/ { in_table = 0 }

# a column line starts with its name and a data type; the continuation lines of
# a check constraint do not
in_table && line ~ /^  [a-z_0-9$#]+ +(varchar2|nvarchar2|char|number|integer|float|clob|nclob|blob|raw|date|timestamp|json|boolean|vector)/ {
  column_name = line
  sub(/^ +/, "", column_name)
  sub(/ .*/, "", column_name)
  print "COLUMN|" toupper(table_name) "." toupper(column_name)
}

line ~ /^create sequence / {
  name = line
  sub(/^create sequence +/, "", name)
  sub(/[ ;].*/, "", name)
  print "SEQUENCE|" toupper(name)
}

line ~ /^create (unique )?index / {
  name = line
  sub(/^create (unique )?index +/, "", name)
  sub(/[ ;].*/, "", name)
  print "INDEX|" toupper(name)
}

{
  rest = line
  while (match(rest, /constraint +[a-z_0-9$#]+/)) {
    name = substr(rest, RSTART, RLENGTH)
    sub(/constraint +/, "", name)
    print "CONSTRAINT|" toupper(name)
    rest = substr(rest, RSTART + RLENGTH)
  }
}
