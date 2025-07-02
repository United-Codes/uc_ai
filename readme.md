# UC AI

A comprehensive Oracle PL/SQL framework for integrating AI models (OpenAI GPT, Anthropic Claude, Google Gemini, etc.) with function calling capabilities. This framework allows AI models to execute database functions through a structured tool system.


## Empowering Oracle Developers

You often hear that **Python is the best language for AI development**, but I don't think that has to be true! Python doesn't have some magic secret sauce you can't get with other languages.

The most important part of AI integration is really just calling an **API** to access Large Language Models (LLMs). Plus, I believe it makes the most sense to put AI features directly into your database, right where your data lives.

It's true that Python (and other languages) have better ways to connect with AI models and frameworks, which definitely makes building AI apps easier. While Oracle is moving in that direction, they only offer this in their 23ai database, which is currently cloud-only. I think it's time we take control and make it easy to access AI models directly in our Oracle databases.

## Quick Demo

```sql
DECLARE
  l_result JSON_OBJECT_T;
BEGIN
  l_result := uc_ai.generate_text(
    p_user_prompt => 'What is APEX Office Print?',
    p_provider => uc_ai.c_provider_openai, -- change to your preferred provider
    p_model => uc_ai_openai.c_model_gpt_4o_mini -- change to your preferred model
  );

  -- Get the AI's response
  DBMS_OUTPUT.PUT_LINE('AI Response: ' || l_result.get_string('final_message'));
END;
/
```

## Documentation

You can find the full documentation at [united-codes.com/products/uc-ai/docs](https://www.united-codes.com/products/uc-ai/docs/).

Here are some key sections to get you started:

- [Installation Guide](https://www.united-codes.com/products/uc-ai/docs/guides/installation/)
- [AI Providers](https://www.united-codes.com/products/uc-ai/docs/guides/providers/)
- [Tools / Function Calling](https://www.united-codes.com/products/uc-ai/docs/guides/tools/)
- API Reference
  - [Generate Text](https://www.united-codes.com/products/uc-ai/docs/api/generate_text/)

## Contributing

Contributions are welcome! Please check out the [roadmap](https://www.united-codes.com/products/uc-ai/docs/other/roadmap/) for planned features and improvements.

Feel free to open discussions for questions and suggestions. If you find bugs, please report them in the issue tracker.

## Acknowledgements

- Thanks alot to the [OraOpenSource Logger](https://github.com/OraOpenSource/Logger) project for the great logging framework
