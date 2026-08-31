# UC AI Tutorials — APEX application

The application behind the [tutorial courses](../../../docs/src/content/docs/tutorial).
One page per course, each one a UC AI Chat region in front of the agent that the
course builds.

| Page | Course | Agent |
| ---- | ------ | ----- |
| 10 | Put an Agent in APEX | `SC_DESK` |
| 20 | Give an Agent a Memory | `MX_DESK` |
| 30 | Secure an Agent | `AP_DESK` |
| 40 | Analyze Data at Scale | `CC_ANALYST` |

The home page changes the model of every one of those agents at once. It writes
the provider and the model to the prompt profile behind each agent, because a
profile agent holds no model of its own.

## Install

1. Install UC AI, and run the setup script of each course you want to use. The
   `About` region of each page names its scripts.
2. Import the application: `make tut-app-import`.
3. Install the supporting objects. They create the backend of the UC AI Chat
   plug-in: `uc_ai_chat_messages`, `uc_ai_chat` and `uc_ai_chat_hook`.

## The supporting-object scripts are symlinks

`uc-ai-tutorials/supporting-objects/install-scripts/` holds five symlinks into
the plug-in repository:

```
../../../../../../../apex-chat/src/ddl/ai_tables.sql
../../../../../../../apex-chat/src/plsql/uc_ai_chat.pks
../../../../../../../apex-chat/src/plsql/uc_ai_chat.pkb
../../../../../../../apex-chat/src/plsql/uc_ai_chat_hook.pks
../../../../../../../apex-chat/src/plsql/uc_ai_chat_hook.pkb
```

The plug-in is a separate product with its own repository, so this repository
carries no copy of it that can go out of date. The links resolve only where the
two repositories sit next to each other, which is the case on a United Codes
development machine and is not the case for a user who clones this repository
alone. That user must run the plug-in scripts by hand.

UC AI itself is not installed by the supporting objects. Install it first.
