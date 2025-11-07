-- @dblinter ignore(g-7410): allow this function in test environment
create or replace function get_oci_compratment_id
  return varchar2
as
begin
  return 'ocid1.tenancy.oc1..aaaaaaaa...';
end get_oci_compratment_id;
/
