create or replace function uc_ai_get_key (
  p_provider in uc_ai.provider_type
)
  return varchar2
as
  e_unhandled_provider exception;
begin
  -- retrieve and return your keys from a secure location the way you prefer
  case p_provider
    when uc_ai.c_provider_openai then 
      return 'change_me';
    when uc_ai.c_provider_anthropic then
      return '...';
    when uc_ai.c_provider_google then
      return '...';
    else 
      raise e_unhandled_provider;
  end case;
exception
  when e_unhandled_provider then
    raise_application_error(-20001, 'No key defined for provider: ' || p_provider);
  when others then
    raise;
end uc_ai_get_key;
/
