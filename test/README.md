# UC AI Tests

Example usage:

```sql
-- single test

set serveroutput on
begin
  ut.run('test_uc_ai_openai.tool_clock_in_user');
end;
/

-- all tests in the package
set serveroutput on
begin
  ut.run('test_uc_ai_openai');
end;
```
