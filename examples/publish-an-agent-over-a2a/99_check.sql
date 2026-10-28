-- ============================================================================
-- UC AI tutorial — "Publish an Agent over A2A"
-- Checks of the booking rule and the tool handlers. No model is called.
-- ============================================================================
-- Run it any time after lesson 3. It prints one PASS or FAIL line for each
-- check, and a summary. It changes no data: the booking that it makes, and the
-- request of the chiller that it removes first, are rolled back. It does not
-- depend on the rows of earlier lessons.
--
-- Every date is relative to the Monday of this week, or to a coverage date of a
-- contract, so the result is the same on every day.
-- ============================================================================

-- @dblinter ignore(g-5010): a tutorial script prints its results with dbms_output on
-- purpose, so the reader sees them directly in SQLcl. A logging framework would hide
-- the output this course asks the reader to compare against the page.

set define off
set serveroutput on size unlimited

savepoint check_start;

declare
  c_ferrolux constant varchar2(100 char) := '{"_ctx":{"a2a_client":"apikey:ferrolux"}}';
  c_friday   constant date := trunc(sysdate, 'IW') + 4;

  l_passed   pls_integer := 0;
  l_total    pls_integer := 0;

  -- asset 1001: press of Ferrolux, contract 88. asset 1002: conveyor of Ferrolux,
  -- with an open request. asset 2001: chiller of Northwind, contract 99, no request.
  l_starts_on date;
  l_ends_on   date;
  l_before    pls_integer;
  l_nw_before pls_integer;
  l_inside    pls_integer;
  l_json      clob;

  -- @dblinter ignore(g-7130): this reporter owns the two counters of the script on purpose,
  -- so that each check is one call and the summary needs no plumbing
  procedure check_that(
    p_name in varchar2
  , p_ok   in boolean
  ) is
  begin
    l_total := l_total + 1;
    if p_ok then
      l_passed := l_passed + 1;
    end if;
    sys.dbms_output.put_line(case when p_ok then 'PASS  ' else 'FAIL  ' end || p_name);
  end check_that;

  function reason_of(p_json in clob) return varchar2 is
  begin
    return json_object_t(p_json).get_string('reason');
  end reason_of;

  function count_of(p_json in clob) return number is
  begin
    return json_object_t(p_json).get_number('count');
  end count_of;

  function same(
    p_a in varchar2
  , p_b in varchar2
  ) return boolean is
  begin
    return p_a = p_b or (p_a is null and p_b is null);
  end same;
begin
  -- The chiller can have an open request, for example from lesson 4. The accept
  -- paths below need a chiller without one, so this removes it inside the
  -- transaction of the script. The rollback at the end puts it back.
  delete from partner_visits
   where asset_id = 2001
     and status = 'REQUESTED';

  select c.starts_on
       , c.ends_on
    into l_starts_on
       , l_ends_on
    from sc_contracts c
   where c.id = 99;

  -- --------------------------------------------------------------------------
  -- Working days
  -- --------------------------------------------------------------------------
  sys.dbms_output.put_line('Working days (today is the Friday ' || to_char(c_friday, 'YYYY-MM-DD') || ')');
  check_that('1 working day after a Friday is the Monday'
           , partner_desk_pkg.add_working_days(c_friday, 1) = c_friday + 3);
  check_that('2 working days after a Friday is the Tuesday'
           , partner_desk_pkg.add_working_days(c_friday, 2) = c_friday + 4);
  check_that('5 working days after a Monday is the next Monday'
           , partner_desk_pkg.add_working_days(c_friday + 3, 5) = c_friday + 10);

  -- --------------------------------------------------------------------------
  -- The four rules, each one refused, and one accept path
  -- --------------------------------------------------------------------------
  sys.dbms_output.put_line('Booking rule');
  check_that('rule 1: the asset of another customer is refused (forged id 2001 for customer 1)'
           , same(partner_desk_pkg.check_visit(2001, c_friday + 8, 1, c_friday), 'NO_ASSET'));
  check_that('rule 1: an asset that does not exist is refused'
           , same(partner_desk_pkg.check_visit(-1, c_friday + 8, 1, c_friday), 'NO_ASSET'));
  check_that('rule 2: the day after the contract is refused'
           , same(partner_desk_pkg.check_visit(2001, l_ends_on + 1, 2, c_friday), 'OUT_OF_COVERAGE'));
  check_that('rule 2: the day before the contract is refused'
           , same(partner_desk_pkg.check_visit(2001, l_starts_on - 1, 2, c_friday), 'OUT_OF_COVERAGE'));
  check_that('rule 3: a second request on the conveyor is refused'
           , same(partner_desk_pkg.check_visit(1002, c_friday + 8, 1, c_friday), 'OPEN_REQUEST'));
  check_that('rule 4: the Monday after a Friday is refused'
           , same(partner_desk_pkg.check_visit(2001, c_friday + 3, 2, c_friday), 'TOO_SOON'));
  check_that('rule 4: the Tuesday after a Friday is accepted (boundary)'
           , partner_desk_pkg.check_visit(2001, c_friday + 4, 2, c_friday) is null);
  check_that('accept: the last day of the contract is accepted'
           , partner_desk_pkg.check_visit(2001, l_ends_on, 2, c_friday) is null);
  check_that('order: rule 2 comes before rule 3 (conveyor, date after the contract)'
           , same(partner_desk_pkg.check_visit(1002, l_ends_on + 1, 1, c_friday), 'OUT_OF_COVERAGE'));

  -- --------------------------------------------------------------------------
  -- The handlers, called as UC AI calls them
  -- --------------------------------------------------------------------------
  sys.dbms_output.put_line('Tool handlers');
  check_that('list_assets for ferrolux returns 2 assets'
           , count_of(partner_desk_pkg.list_assets(c_ferrolux)) = 2);
  check_that('list_assets for northwind returns 1 asset'
           , count_of(partner_desk_pkg.list_assets('{"_ctx":{"a2a_client":"apikey:northwind"}}')) = 1);
  check_that('list_assets for ferrolux does not name an asset of northwind'
           , instr(partner_desk_pkg.list_assets(c_ferrolux), 'NW-') = 0);
  check_that('a forged customer_id in the arguments is ignored'
           , count_of(partner_desk_pkg.list_assets(
               '{"customer_id":2,"_ctx":{"a2a_client":"apikey:ferrolux"}}')) = 2);
  check_that('an unknown client is refused, not given an empty list'
           , same(reason_of(partner_desk_pkg.list_assets('{"_ctx":{"a2a_client":"apikey:unknown"}}')), 'UNKNOWN_CLIENT'));
  check_that('a run without a client is refused'
           , same(reason_of(partner_desk_pkg.list_assets('{"_ctx":{}}')), 'UNKNOWN_CLIENT'));
  check_that('history of an asset of another customer is refused'
           , same(reason_of(partner_desk_pkg.get_asset_history(
               '{"asset_tag":"NW-CHILL-02","_ctx":{"a2a_client":"apikey:ferrolux"}}')), 'NO_ASSET'));
  check_that('history of the press returns its service calls'
           , count_of(partner_desk_pkg.get_asset_history(
               '{"asset_tag":"FX-PRESS-01","_ctx":{"a2a_client":"apikey:ferrolux"}}')) >= 1);
  check_that('a foreign asset and a missing asset get the same answer'
           , replace(partner_desk_pkg.get_asset_history(
               '{"asset_tag":"NW-CHILL-02","_ctx":{"a2a_client":"apikey:ferrolux"}}'), 'NW-CHILL-02', 'X')
           = replace(partner_desk_pkg.get_asset_history(
               '{"asset_tag":"XX-NOPE-99","_ctx":{"a2a_client":"apikey:ferrolux"}}'), 'XX-NOPE-99', 'X'));

  -- --------------------------------------------------------------------------
  -- book_visit: refusals insert nothing, an accepted request inserts one row
  -- --------------------------------------------------------------------------
  sys.dbms_output.put_line('book_visit');
  -- @dblinter ignore(g-8110): these count rows to compare two numbers, they are not an existence test
  select count(*) into l_before from partner_visits;
  -- @dblinter ignore(g-8110): this counts rows to compare two numbers, it is not an existence test
  select count(*) into l_nw_before from partner_visits where client_id = 'apikey:northwind';

  l_json := partner_desk_pkg.book_visit(
    '{"asset_tag":"NW-CHILL-02","visit_date":"'
    || to_char(partner_desk_pkg.add_working_days(trunc(sysdate), 5), 'YYYY-MM-DD')
    || '","_ctx":{"a2a_client":"apikey:ferrolux"}}');
  select count(*) into l_inside from partner_visits;
  check_that('ferrolux asks for the chiller of northwind: refused, no row'
           , same(reason_of(l_json), 'NO_ASSET') and l_inside = l_before);

  l_json := partner_desk_pkg.book_visit(
    '{"asset_tag":"FX-CONV-07","visit_date":"'
    || to_char(partner_desk_pkg.add_working_days(trunc(sysdate), 5), 'YYYY-MM-DD')
    || '","_ctx":{"a2a_client":"apikey:ferrolux"}}');
  select count(*) into l_inside from partner_visits;
  check_that('ferrolux asks for a second visit on the conveyor: refused, no row'
           , same(reason_of(l_json), 'OPEN_REQUEST') and l_inside = l_before);

  l_json := partner_desk_pkg.book_visit(
    '{"asset_tag":"NW-CHILL-02","visit_date":"not a date","_ctx":{"a2a_client":"apikey:northwind"}}');
  check_that('a date that is not YYYY-MM-DD is refused'
           , same(reason_of(l_json), 'BAD_DATE'));

  l_json := partner_desk_pkg.book_visit(
    '{"asset_tag":"NW-CHILL-02","visit_date":"'
    || to_char(partner_desk_pkg.add_working_days(trunc(sysdate), 5), 'YYYY-MM-DD')
    || '","_ctx":{"a2a_client":"apikey:northwind"}}');
  select count(*) into l_inside from partner_visits where client_id = 'apikey:northwind';
  check_that('northwind asks for its chiller: one new REQUESTED row for apikey:northwind'
           , json_object_t(l_json).get_string('status') = 'requested' and l_inside = l_nw_before + 1);

  sys.dbms_output.put_line(null);
  sys.dbms_output.put_line(l_passed || ' of ' || l_total || ' checks passed.');
end;
/

-- Undo the writes above: the booking of the chiller, and the removed request.
rollback to check_start;

select count(*) as northwind_rows_after_rollback
  from partner_visits
 where client_id = 'apikey:northwind';
