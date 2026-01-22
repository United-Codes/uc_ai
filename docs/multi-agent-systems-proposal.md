# Multi-Agent Systems Implementation Proposal for UC AI

**Author**: Analysis for UC AI Framework
**Date**: January 22, 2026
**Status**: Proposal Draft

## Executive Summary

This proposal outlines a comprehensive architecture for implementing multi-agent systems in UC AI, an Oracle PL/SQL framework for AI integration. The design leverages the existing **prompt profiles** foundation while introducing new components to support both **workflow patterns** (sequential, conditional, parallel) and **autonomous patterns** (orchestrator, handoff, conversation-driven).

**Key Design Principles:**
1. **Database-native**: Fully leverage Oracle PL/SQL capabilities
2. **Declarative configuration**: Store agent definitions and workflows in tables
3. **Progressive enhancement**: Build on existing prompt profiles infrastructure
4. **Composability**: Allow autonomous patterns to invoke workflow patterns
5. **Ease of use**: Minimize boilerplate for common use cases

---

## Background Analysis

### Current State

UC AI currently provides:
- **Prompt Profiles**: Versioned, reusable prompt templates with parameter substitution
- **Tools/Function Calling**: Ability for AI models to execute database functions
- **Provider Abstraction**: Unified interface across multiple AI providers (OpenAI, Anthropic, Google, etc.)
- **Structured Output**: JSON schema-based response validation

### The Challenge

Multi-agent systems require coordination between multiple AI agents, each with specialized roles. Two distinct pattern families emerge:

**Workflow Patterns** (Deterministic):
- **Sequential**: Agent A → Agent B → Agent C (linear flow)
- **Conditional**: Route to different agents based on conditions
- **Parallel**: Execute multiple agents concurrently, aggregate results
- **Loop**: Repeat agent execution until condition met

**Autonomous Patterns** (Dynamic):
- **Orchestrator**: Central agent delegates to specialized agents
- **Handoff**: Agents pass control to each other based on capability
- **Conversation-driven**: Multiple agents collaborate in dialogue

---

## Proposed Architecture

### 1. Core Components

#### 1.1 Agent Definition Table

Extend the concept of prompt profiles to full **agents**:

```sql
CREATE TABLE uc_ai_agents (
  id                     NUMBER PRIMARY KEY,
  code                   VARCHAR2(255) NOT NULL,
  version                NUMBER DEFAULT 1 NOT NULL,
  status                 VARCHAR2(50) DEFAULT 'draft' NOT NULL,
  description            VARCHAR2(4000) NOT NULL,
  agent_type             VARCHAR2(50) NOT NULL, -- 'profile', 'workflow', 'orchestrator', 'handoff', 'conversation'
  
  -- For agent_type = 'profile'
  prompt_profile_code    VARCHAR2(255),  -- References code, not ID (uses latest active version)
  prompt_profile_version NUMBER,         -- Optional: NULL = always use latest active version
  
  -- For agent_type = 'workflow'
  workflow_definition    CLOB,    -- JSON workflow definition
  
  -- For agent_type = 'orchestrator'/'handoff'/'conversation'
  orchestration_config   CLOB,    -- JSON config for autonomous patterns
  
  -- Shared configuration
  input_schema           CLOB,    -- JSON schema for input validation
  output_schema          CLOB,    -- JSON schema for output validation
  timeout_seconds        NUMBER,
  max_iterations         NUMBER,
  max_history_messages   NUMBER,  -- For conversation patterns: sliding window size
  
  created_by             VARCHAR2(255) NOT NULL,
  created_at             TIMESTAMP NOT NULL,
  updated_by             VARCHAR2(255) NOT NULL,
  updated_at             TIMESTAMP NOT NULL,
  
  CONSTRAINT uc_ai_agents_uk UNIQUE (code, version),
  CONSTRAINT uc_ai_agents_status_ck CHECK (status IN ('draft', 'active', 'archived')),
  CONSTRAINT uc_ai_agents_type_ck CHECK (agent_type IN 
    ('profile', 'workflow', 'orchestrator', 'handoff', 'conversation'))
);

-- Note: Only one version of an agent can be 'active' at a time per code
-- This mirrors the prompt_profiles versioning pattern
CREATE UNIQUE INDEX uc_ai_agents_active_uk ON uc_ai_agents(code) 
  WHERE status = 'active';

CREATE INDEX uc_ai_agents_code_idx ON uc_ai_agents(code, version, status);
```

#### 1.2 Agent Relationships (JSON-Based)

Agent relationships (workflow steps, delegates, handoff targets, conversation participants) are stored **within the JSON configuration** (`workflow_definition` or `orchestration_config`) rather than a separate table.

**Rationale**:
- Simpler data model without sync issues
- JSON is the natural format for these nested configurations
- Relationships are always accessed in context of the parent agent

**Referential Integrity via Validation**:
- On `create_agent`: Validate all referenced agent codes exist
- On `delete_agent`: Check if agent is referenced by other agents and raise error if so
- References use `agent_code` (not ID) - always resolves to latest active version

```sql
-- Validation happens in uc_ai_agents_api package:
-- 1. On create/update: parse JSON, extract agent_code references, verify they exist
-- 2. On delete: query all agents' JSON configs to check for references

FUNCTION validate_agent_references(
  p_workflow_definition   IN CLOB,
  p_orchestration_config  IN CLOB
) RETURN BOOLEAN;

PROCEDURE check_agent_not_referenced(
  p_agent_code IN VARCHAR2
);  -- Raises exception if referenced
```

#### 1.3 Execution Context Table

Store state for long-running agent executions:

```sql
CREATE TABLE uc_ai_agent_executions (
  id                     NUMBER PRIMARY KEY,
  agent_id               NUMBER NOT NULL,
  parent_execution_id    NUMBER,  -- For nested agent calls
  session_id             VARCHAR2(255),  -- Group related executions (use SYS_GUID())
  
  input_parameters       CLOB,  -- JSON input
  current_state          CLOB,  -- JSON state during execution
  output_result          CLOB,  -- JSON output
  
  status                 VARCHAR2(50) NOT NULL, -- 'running', 'completed', 'failed', 'timeout'
  iteration_count        NUMBER DEFAULT 0,
  tool_calls_count       NUMBER DEFAULT 0,
  
  -- Token and cost tracking (critical for multi-agent systems)
  total_input_tokens     NUMBER DEFAULT 0,
  total_output_tokens    NUMBER DEFAULT 0,
  
  started_at             TIMESTAMP WITH TIME ZONE NOT NULL,
  completed_at           TIMESTAMP WITH TIME ZONE,
  error_message          VARCHAR2(4000),
  
  CONSTRAINT uc_ai_agent_exec_agent_fk FOREIGN KEY (agent_id) 
    REFERENCES uc_ai_agents(id),
  CONSTRAINT uc_ai_agent_exec_parent_fk FOREIGN KEY (parent_execution_id) 
    REFERENCES uc_ai_agent_executions(id),
  CONSTRAINT uc_ai_agent_exec_status_ck CHECK (status IN 
    ('running', 'completed', 'failed', 'timeout'))
);

CREATE INDEX uc_ai_agent_exec_session_idx ON uc_ai_agent_executions(session_id);
CREATE INDEX uc_ai_agent_exec_status_idx ON uc_ai_agent_executions(status, started_at);
```

### 2. Workflow Patterns Implementation

#### 2.1 Workflow Definition JSON Schema

For `agent_type = 'workflow'`, the `workflow_definition` CLOB contains:

```json
{
  "workflow_type": "sequential|conditional|parallel|loop",
  "steps": [
    {
      "step_id": "step_1",
      "agent_code": "data_analyzer",  // Always uses latest active version
      "input_mapping": {
        "agent_param": "${workflow_input.field}"
      },
      "output_mapping": {
        "workflow_state.analysis": "${step_output}"
      },
      "condition": {
        "type": "json_path|plsql",
        "expression": "$.priority == 'high'"  // PL/SQL evaluated via APEX_PLUGIN_UTIL
      },
      "timeout_seconds": 30,
      "on_error": "continue|stop|retry"
    }
  ],
  "parallel_config": {
    "execution_mode": "wait_all|wait_first|wait_n",
    "aggregation_strategy": "merge|array|custom"
  },
  "loop_config": {
    "max_iterations": 5,
    "exit_condition": {
      "type": "json_path|plsql",
      "expression": "$.completed == true"
    }
  }
}
```

#### 2.2 Workflow Execution API

```sql
-- Package: uc_ai_agents_api
FUNCTION execute_workflow_agent(
  p_agent_code        IN VARCHAR2,
  p_agent_version     IN NUMBER DEFAULT NULL,
  p_input_parameters  IN JSON_OBJECT_T,
  p_session_id        IN VARCHAR2 DEFAULT NULL
) RETURN JSON_OBJECT_T;
```

#### 2.3 Implementation Strategy

**Sequential Workflows**:
```sql
-- Execute steps in order, passing output to next step
FOR step IN (
  SELECT * FROM workflow_steps 
  ORDER BY execution_order
) LOOP
  l_step_input := map_inputs(step.input_mapping, l_workflow_state);
  l_step_output := execute_agent(step.agent_code, l_step_input);
  l_workflow_state := merge_outputs(step.output_mapping, l_step_output);
END LOOP;
```

**Conditional Workflows**:
```sql
-- Evaluate conditions to determine next step
FOR step IN (SELECT * FROM workflow_steps) LOOP
  IF evaluate_condition(step.condition, l_workflow_state) THEN
    l_step_output := execute_agent(step.agent_code, l_step_input);
    EXIT WHEN step.exit_on_match = 1;
  END IF;
END LOOP;
```

**Condition Expression Evaluation**:
```sql
-- Use APEX_PLUGIN_UTIL for safe PL/SQL expression evaluation with bind variable support
FUNCTION evaluate_condition(
  p_condition      IN JSON_OBJECT_T,
  p_workflow_state IN JSON_OBJECT_T
) RETURN BOOLEAN
IS
  l_type       VARCHAR2(50) := p_condition.get_string('type');
  l_expression VARCHAR2(4000) := p_condition.get_string('expression');
  l_bind_list  apex_plugin_util.t_bind_list;
BEGIN
  IF l_type = 'json_path' THEN
    -- Use Oracle JSON_EXISTS for JSON path expressions
    RETURN JSON_EXISTS(p_workflow_state.to_clob, l_expression);
    
  ELSIF l_type = 'plsql' THEN
    -- Safely evaluate PL/SQL expression using APEX_PLUGIN_UTIL
    -- This handles bind variable binding and prevents SQL injection
    -- Bind workflow state values as :VARNAME
    populate_bind_list(l_bind_list, p_workflow_state);
    
    RETURN apex_plugin_util.get_plsql_expr_result_boolean(
      p_plsql_expression => l_expression,
      p_auto_bind_items  => FALSE,  -- Don't auto-bind APEX items
      p_bind_list        => l_bind_list
    );
  ELSE
    RAISE_APPLICATION_ERROR(-20001, 'Unknown condition type: ' || l_type);
  END IF;
END;
```

**Parallel Workflows**:
```sql
-- Use DBMS_PARALLEL_EXECUTE for parallel execution with synchronous waiting
DECLARE
  l_task_name VARCHAR2(255) := 'AGENT_PARALLEL_' || SYS_GUID();
  l_sql_stmt  CLOB;
BEGIN
  -- Create the parallel task
  DBMS_PARALLEL_EXECUTE.create_task(task_name => l_task_name);
  
  -- Create chunks for each parallel step
  DBMS_PARALLEL_EXECUTE.create_chunks_by_sql(
    task_name => l_task_name,
    sql_stmt  => 'SELECT step_id FROM workflow_steps WHERE parallel_group = 1',
    by_rowid  => FALSE
  );
  
  -- Execute all chunks in parallel (synchronous - waits for completion)
  l_sql_stmt := 'BEGIN execute_agent_step(:start_id, :end_id); END;';
  DBMS_PARALLEL_EXECUTE.run_task(
    task_name      => l_task_name,
    sql_stmt       => l_sql_stmt,
    language_flag  => DBMS_SQL.NATIVE,
    parallel_level => 4  -- Configurable parallelism
  );
  
  -- Check for failures and handle retries
  IF DBMS_PARALLEL_EXECUTE.task_status(l_task_name) = DBMS_PARALLEL_EXECUTE.FINISHED_WITH_ERROR THEN
    -- Retry failed chunks (built-in retry support)
    DBMS_PARALLEL_EXECUTE.resume_task(l_task_name);
  END IF;
  
  -- Aggregate results from execution table
  l_aggregated := aggregate_results(l_task_name, p_strategy);
  
  -- Cleanup
  DBMS_PARALLEL_EXECUTE.drop_task(l_task_name);
END;
```

**Note**: `DBMS_PARALLEL_EXECUTE` provides built-in synchronous waiting (`run_task` blocks until complete) and native retry support via `resume_task`.

**Loop Workflows**:
```sql
-- Iterate until condition met or max iterations
WHILE l_iteration < p_max_iterations LOOP
  l_output := execute_agent(p_agent_code, l_input);
  EXIT WHEN evaluate_condition(p_exit_condition, l_output);
  l_iteration := l_iteration + 1;
  l_input := l_output; -- Feedback loop
END LOOP;
```

#### 2.4 User Experience Example

```sql
DECLARE
  l_agent_id NUMBER;
  l_workflow_def CLOB;
  l_result JSON_OBJECT_T;
  l_input JSON_OBJECT_T := JSON_OBJECT_T();
BEGIN
  -- Define workflow
  l_workflow_def := '{
    "workflow_type": "sequential",
    "steps": [
      {
        "step_id": "classify",
        "agent_code": "text_classifier",
        "input_mapping": {"text": "${input.customer_feedback}"},
        "output_mapping": {"category": "${step_output.category}"}
      },
      {
        "step_id": "analyze",
        "agent_code": "sentiment_analyzer",
        "input_mapping": {"text": "${input.customer_feedback}"},
        "output_mapping": {"sentiment": "${step_output.sentiment}"}
      },
      {
        "step_id": "summarize",
        "agent_code": "summarizer",
        "input_mapping": {
          "text": "${input.customer_feedback}",
          "category": "${workflow.category}",
          "sentiment": "${workflow.sentiment}"
        }
      }
    ]
  }';
  
  -- Create workflow agent
  l_agent_id := uc_ai_agents_api.create_agent(
    p_code => 'customer_feedback_pipeline',
    p_description => 'Sequential analysis of customer feedback',
    p_agent_type => 'workflow',
    p_workflow_definition => l_workflow_def,
    p_status => 'active'
  );
  
  -- Execute workflow
  l_input.put('customer_feedback', 'The product is great but delivery was slow.');
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code => 'customer_feedback_pipeline',
    p_input_parameters => l_input
  );
  
  DBMS_OUTPUT.PUT_LINE('Summary: ' || l_result.get_string('summary'));
END;
/
```

### 3. Autonomous Patterns Implementation

#### 3.1 Orchestrator Pattern

The orchestrator pattern uses a **central AI agent** to delegate tasks to specialized agents. This is implemented by:

1. **Making child agents available as tools** to the orchestrator
2. The orchestrator AI decides which agents to invoke and when
3. Results are returned to orchestrator for synthesis

**Orchestration Config JSON**:
```json
{
  "pattern_type": "orchestrator",
  "orchestrator_profile_code": "research_coordinator_prompt",  // Uses latest active version
  "delegate_agents": [
    {
      "agent_code": "sql_expert",  // Always uses latest active version
      "tags": ["database", "query"],
      "tool_name": "consult_sql_expert",
      "tool_description": "Get help with SQL queries and database optimization"
    },
    {
      "agent_code": "security_expert",
      "tool_name": "consult_security_expert",
      "tool_description": "Get security recommendations and vulnerability assessments"
    }
  ],
  "synthesis_prompt": "Synthesize the responses from specialized agents into a coherent answer.",
  "max_delegations": 5
}
```

**Note**: All `agent_code` references resolve to the **latest active version** of that agent. This ensures workflows automatically use updated agent versions without reconfiguration.

**Implementation**:
```sql
FUNCTION execute_orchestrator_agent(
  p_agent_id          IN NUMBER,
  p_input_parameters  IN JSON_OBJECT_T
) RETURN JSON_OBJECT_T
IS
  l_config JSON_OBJECT_T;
  l_delegates JSON_ARRAY_T;
  l_tool_id NUMBER;
  l_tool_id_list apex_t_number := apex_t_number();
  l_result JSON_OBJECT_T;
BEGIN
  -- Get orchestration config
  SELECT orchestration_config INTO l_config_clob
  FROM uc_ai_agents WHERE id = p_agent_id;
  
  l_config := JSON_OBJECT_T(l_config_clob);
  l_delegates := l_config.get_array('delegate_agents');
  
  -- Dynamically register delegate agents as tools
  FOR i IN 0..l_delegates.get_size - 1 LOOP
    l_delegate := JSON_OBJECT_T(l_delegates.get(i));
    
    l_tool_id := register_agent_as_tool(
      p_agent_code => l_delegate.get_string('agent_code'),  -- Uses latest active
      p_tool_name => l_delegate.get_string('tool_name'),
      p_tool_description => l_delegate.get_string('tool_description')
    );
    l_tool_id_list.extend;
    l_tool_id_list(l_tool_id_list.count) := l_tool_id;
  END LOOP;
  
  -- Execute orchestrator with tools enabled (with proper cleanup on error)
  BEGIN
    uc_ai.g_enable_tools := TRUE;
    l_result := uc_ai_prompt_profiles_api.execute_profile(
      p_code => l_config.get_string('orchestrator_profile_code'),  -- Uses latest active version
      p_parameters => p_input_parameters
    );
  EXCEPTION
    WHEN OTHERS THEN
      -- Always cleanup temporary tools, even on error
      cleanup_agent_tools(l_tool_id_list);
      RAISE;
  END;
  
  -- Cleanup temporary tools on success
  cleanup_agent_tools(l_tool_id_list);
  
  RETURN l_result;
END;
```

**Dynamic Tool Registration**:
```sql
FUNCTION register_agent_as_tool(
  p_agent_code        IN VARCHAR2,
  p_tool_name         IN VARCHAR2,
  p_tool_description  IN VARCHAR2
) RETURN NUMBER
IS
  l_tool_id NUMBER;
  l_function_call CLOB;
BEGIN
  -- Create dynamic function call that executes the agent
  l_function_call := '
    DECLARE
      l_input JSON_OBJECT_T := JSON_OBJECT_T();
      l_result JSON_OBJECT_T;
    BEGIN
      -- Map tool parameters to agent input
      #PARAM_MAPPING#
      
      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code => ''' || p_agent_code || ''',
        p_input_parameters => l_input
      );
      
      RETURN l_result.get_clob(''final_message'');
    END;';
  
  -- Register as temporary tool
  l_tool_id := uc_ai_tools_api.create_tool(
    p_code => p_tool_name,
    p_description => p_tool_description,
    p_function_call => l_function_call,
    p_active => 1,
    p_temporary => TRUE  -- Flag for cleanup
  );
  
  RETURN l_tool_id;
END;
```

#### 3.2 Handoff Pattern

Agents pass control to each other based on capability and context.

**Orchestration Config JSON**:
```json
{
  "pattern_type": "handoff",
  "initial_agent_code": "triage_agent",
  "handoff_agents": [
    {
      "agent_code": "technical_support",
      "handoff_triggers": ["technical", "bug", "error"],
      "capabilities": ["debugging", "technical_advice"]
    },
    {
      "agent_code": "sales_agent",
      "handoff_triggers": ["pricing", "purchase", "upgrade"],
      "capabilities": ["sales", "billing"]
    }
  ],
  "handoff_mechanism": "structured_output",
  "max_handoffs": 3,
  "handoff_schema": {
    "type": "object",
    "properties": {
      "should_handoff": {"type": "boolean"},
      "target_agent": {"type": "string"},
      "handoff_reason": {"type": "string"},
      "context_for_next_agent": {"type": "string"}
    }
  }
}
```

**Implementation**:
```sql
FUNCTION execute_handoff_agent(
  p_agent_id          IN NUMBER,
  p_input_parameters  IN JSON_OBJECT_T,
  p_session_id        IN VARCHAR2
) RETURN JSON_OBJECT_T
IS
  l_current_agent VARCHAR2(255);
  l_handoff_count NUMBER := 0;
  l_max_handoffs NUMBER;
  l_conversation_history JSON_ARRAY_T := JSON_ARRAY_T();
  l_result JSON_OBJECT_T;
  l_handoff_decision JSON_OBJECT_T;
BEGIN
  -- Get initial agent and config
  SELECT orchestration_config INTO l_config_clob
  FROM uc_ai_agents WHERE id = p_agent_id;
  
  l_config := JSON_OBJECT_T(l_config_clob);
  l_current_agent := l_config.get_string('initial_agent_code');
  l_max_handoffs := l_config.get_number('max_handoffs');
  
  -- Handoff loop
  WHILE l_handoff_count < l_max_handoffs LOOP
    -- Execute current agent
    l_result := uc_ai_agents_api.execute_agent(
      p_agent_code => l_current_agent,
      p_input_parameters => p_input_parameters
    );
    
    -- Add to conversation history
    l_conversation_history.append(JSON_OBJECT_T(
      JSON_OBJECT(
        'agent' VALUE l_current_agent,
        'response' VALUE l_result.get_clob('final_message')
      )
    ));
    
    -- Check if agent wants to handoff
    l_handoff_decision := JSON_OBJECT_T(l_result.get_clob('handoff_decision'));
    EXIT WHEN NOT l_handoff_decision.get_boolean('should_handoff');
    
    -- Prepare context for next agent
    l_current_agent := l_handoff_decision.get_string('target_agent');
    p_input_parameters.put('handoff_context', l_handoff_decision.get_string('context_for_next_agent'));
    p_input_parameters.put('conversation_history', l_conversation_history);
    
    l_handoff_count := l_handoff_count + 1;
  END LOOP;
  
  -- Return final result with full history
  l_result.put('conversation_history', l_conversation_history);
  l_result.put('handoff_count', l_handoff_count);
  
  RETURN l_result;
END;
```

**Agent Handoff via Structured Output**:
```sql
-- Each participating agent has a response schema that includes handoff decision
l_response_schema := '{
  "type": "object",
  "properties": {
    "answer": {"type": "string"},
    "handoff_decision": {
      "type": "object",
      "properties": {
        "should_handoff": {"type": "boolean"},
        "target_agent": {"type": "string", "enum": ["technical_support", "sales_agent", "none"]},
        "handoff_reason": {"type": "string"},
        "context_for_next_agent": {"type": "string"}
      }
    }
  }
}';
```

#### 3.3 Conversation-Driven Pattern

Multiple agents collaborate in a dialogue, either round-robin or AI-driven.

**Orchestration Config JSON**:
```json
{
  "pattern_type": "conversation",
  "conversation_mode": "round_robin|ai_driven",
  "participant_agents": [
    {
      "agent_code": "architect",  // Uses latest active version
      "role": "Design software architecture",
      "speaks_first": true
    },
    {
      "agent_code": "developer",
      "role": "Implement the design"
    },
    {
      "agent_code": "tester",
      "role": "Identify bugs and issues"
    }
  ],
  "moderator_agent_code": "project_manager",  // For ai_driven mode
  "max_turns": 10,
  "history_management": {
    "strategy": "sliding_window|summarize|full",
    "max_messages": 20,           // For sliding_window: keep last N messages
    "summarize_after": 10,        // For summarize: summarize after N messages
    "summarizer_agent_code": "conversation_summarizer"  // Agent to create summaries
  },
  "completion_criteria": {
    "type": "structured_output",
    "schema": {
      "type": "object",
      "properties": {
        "discussion_complete": {"type": "boolean"},
        "final_decision": {"type": "string"}
      }
    }
  }
}
```

**History Management Strategies**:
- `full`: Keep all messages (default, watch for context limits)
- `sliding_window`: Keep only the last N messages
- `summarize`: Periodically summarize older messages using a summarizer agent

**Round-Robin Implementation**:
```sql
FUNCTION execute_conversation_roundrobin(
  p_config            IN JSON_OBJECT_T,
  p_input_parameters  IN JSON_OBJECT_T
) RETURN JSON_OBJECT_T
IS
  l_participants JSON_ARRAY_T;
  l_conversation JSON_ARRAY_T := JSON_ARRAY_T();
  l_turn_count NUMBER := 0;
  l_max_turns NUMBER;
  l_current_state JSON_OBJECT_T := p_input_parameters;
BEGIN
  l_participants := p_config.get_array('participant_agents');
  l_max_turns := p_config.get_number('max_turns');
  
  -- Round-robin conversation
  WHILE l_turn_count < l_max_turns LOOP
    FOR i IN 0..l_participants.get_size - 1 LOOP
      l_participant := JSON_OBJECT_T(l_participants.get(i));
      
      -- Prepare input with conversation history
      l_agent_input := JSON_OBJECT_T(l_current_state.to_clob);
      l_agent_input.put('conversation_history', l_conversation);
      l_agent_input.put('your_role', l_participant.get_string('role'));
      
      -- Execute agent
      l_result := uc_ai_agents_api.execute_agent(
        p_agent_code => l_participant.get_string('agent_code'),
        p_input_parameters => l_agent_input
      );
      
      -- Add to conversation
      l_conversation.append(JSON_OBJECT_T(
        JSON_OBJECT(
          'agent' VALUE l_participant.get_string('agent_code'),
          'role' VALUE l_participant.get_string('role'),
          'message' VALUE l_result.get_clob('final_message'),
          'turn' VALUE l_turn_count
        )
      ));
      
      -- Check completion criteria
      IF check_completion(l_result, p_config.get_object('completion_criteria')) THEN
        GOTO conversation_complete;
      END IF;
    END LOOP;
    
    l_turn_count := l_turn_count + 1;
  END LOOP;
  
  <<conversation_complete>>
  RETURN JSON_OBJECT_T(
    JSON_OBJECT(
      'conversation' VALUE l_conversation,
      'turns' VALUE l_turn_count,
      'completed' VALUE TRUE
    )
  );
END;
```

**AI-Driven Implementation**:
```sql
-- Moderator agent decides who speaks next using structured output
l_moderator_result := uc_ai_agents_api.execute_agent(
  p_agent_code => l_config.get_string('moderator_agent_code'),
  p_input_parameters => JSON_OBJECT_T(JSON_OBJECT(
    'conversation_history' VALUE l_conversation,
    'available_agents' VALUE l_participants,
    'task' VALUE 'Decide which agent should speak next and what they should address'
  ))
);

l_next_speaker := l_moderator_result.get_object('next_speaker');
l_agent_code := l_next_speaker.get_string('agent_code');
l_directive := l_next_speaker.get_string('directive');
```

### 4. Composability: Autonomous → Workflow

Enable autonomous patterns to invoke workflow patterns by treating workflows as agents.

**Example: Orchestrator delegates to a Sequential Workflow**

```sql
DECLARE
  l_orchestrator_id NUMBER;
  l_workflow_id NUMBER;
BEGIN
  -- Create sequential workflow for data processing
  l_workflow_id := uc_ai_agents_api.create_agent(
    p_code => 'data_processing_pipeline',
    p_agent_type => 'workflow',
    p_workflow_definition => '{
      "workflow_type": "sequential",
      "steps": [
        {"agent_code": "data_cleaner"},
        {"agent_code": "data_transformer"},
        {"agent_code": "data_validator"}
      ]
    }'
  );
  
  -- Create orchestrator that can delegate to the workflow
  l_orchestrator_id := uc_ai_agents_api.create_agent(
    p_code => 'data_orchestrator',
    p_agent_type => 'orchestrator',
    p_orchestration_config => '{
      "orchestrator_profile_code": "data_orchestrator_prompt",
      "delegate_agents": [
        {
          "agent_code": "data_processing_pipeline",
          "tool_name": "process_data",
          "tool_description": "Clean, transform, and validate data"
        },
        {
          "agent_code": "report_generator",
          "tool_name": "generate_report"
        }
      ]
    }'
  );
END;
/
-- Note: All agent_code references use latest active version automatically
```

The orchestrator AI can now decide: "I need to process this data, let me use the `process_data` tool" → which executes the entire sequential workflow.

### 5. Complete API Design

```sql
-- Package: uc_ai_agents_api

-- ============================================================================
-- Agent Management
-- ============================================================================

FUNCTION create_agent(
  p_code                   IN VARCHAR2,
  p_description            IN VARCHAR2,
  p_agent_type             IN VARCHAR2,  -- 'profile', 'workflow', 'orchestrator', etc.
  p_prompt_profile_code    IN VARCHAR2 DEFAULT NULL,  -- References by code, not ID
  p_prompt_profile_version IN NUMBER DEFAULT NULL,    -- NULL = always use latest active
  p_workflow_definition    IN CLOB DEFAULT NULL,
  p_orchestration_config   IN CLOB DEFAULT NULL,
  p_input_schema           IN CLOB DEFAULT NULL,
  p_output_schema          IN CLOB DEFAULT NULL,
  p_max_history_messages   IN NUMBER DEFAULT NULL,    -- For conversation patterns
  p_version                IN NUMBER DEFAULT 1,
  p_status                 IN VARCHAR2 DEFAULT 'draft'
) RETURN NUMBER;
-- Note: On create, validates all referenced agent_codes in workflow/orchestration configs exist

PROCEDURE update_agent(
  p_agent_id              IN NUMBER,
  p_description           IN VARCHAR2 DEFAULT NULL,
  p_workflow_definition   IN CLOB DEFAULT NULL,
  p_orchestration_config  IN CLOB DEFAULT NULL,
  p_input_schema          IN CLOB DEFAULT NULL,
  p_output_schema         IN CLOB DEFAULT NULL
);

PROCEDURE delete_agent(
  p_agent_id IN NUMBER
);

PROCEDURE change_agent_status(
  p_agent_id IN NUMBER,
  p_status   IN VARCHAR2
);

FUNCTION get_agent(
  p_agent_code    IN VARCHAR2,
  p_agent_version IN NUMBER DEFAULT NULL  -- NULL = latest active
) RETURN uc_ai_agents%ROWTYPE;

-- ============================================================================
-- Agent Execution
-- ============================================================================

FUNCTION execute_agent(
  p_agent_code        IN VARCHAR2,
  p_agent_version     IN NUMBER DEFAULT NULL,
  p_input_parameters  IN JSON_OBJECT_T,
  p_session_id        IN VARCHAR2 DEFAULT NULL,
  p_parent_exec_id    IN NUMBER DEFAULT NULL
) RETURN JSON_OBJECT_T;

FUNCTION execute_agent(
  p_agent_id          IN NUMBER,
  p_input_parameters  IN JSON_OBJECT_T,
  p_session_id        IN VARCHAR2 DEFAULT NULL,
  p_parent_exec_id    IN NUMBER DEFAULT NULL
) RETURN JSON_OBJECT_T;

-- ============================================================================
-- Session Management
-- ============================================================================

FUNCTION generate_session_id RETURN VARCHAR2;
-- Returns: SYS_GUID() formatted as VARCHAR2 for grouping related executions

-- ============================================================================
-- Validation Functions
-- ============================================================================

FUNCTION validate_agent_references(
  p_workflow_definition   IN CLOB DEFAULT NULL,
  p_orchestration_config  IN CLOB DEFAULT NULL
) RETURN BOOLEAN;
-- Validates all agent_code references in configs exist as active agents

PROCEDURE check_agent_not_referenced(
  p_agent_code IN VARCHAR2
);
-- Raises exception if agent is referenced by other agents (call before delete)

-- ============================================================================
-- Execution History
-- ============================================================================

FUNCTION get_execution_history(
  p_session_id        IN VARCHAR2 DEFAULT NULL,
  p_agent_code        IN VARCHAR2 DEFAULT NULL,
  p_status            IN VARCHAR2 DEFAULT NULL,
  p_start_date        IN TIMESTAMP DEFAULT NULL,
  p_end_date          IN TIMESTAMP DEFAULT NULL
) RETURN SYS_REFCURSOR;

FUNCTION get_execution_details(
  p_execution_id IN NUMBER
) RETURN JSON_OBJECT_T;

-- ============================================================================
-- Workflow-Specific Functions
-- ============================================================================

FUNCTION create_sequential_workflow(
  p_code              IN VARCHAR2,
  p_description       IN VARCHAR2,
  p_agent_steps       IN JSON_ARRAY_T  -- Array of agent codes in order
) RETURN NUMBER;

FUNCTION create_parallel_workflow(
  p_code              IN VARCHAR2,
  p_description       IN VARCHAR2,
  p_agent_steps       IN JSON_ARRAY_T,
  p_aggregation_strategy IN VARCHAR2 DEFAULT 'merge'
) RETURN NUMBER;

-- ============================================================================
-- Helper Functions
-- ============================================================================

FUNCTION validate_workflow_definition(
  p_workflow_definition IN CLOB
) RETURN BOOLEAN;

FUNCTION validate_orchestration_config(
  p_orchestration_config IN CLOB
) RETURN BOOLEAN;
```

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- Create new tables: `uc_ai_agents`, `uc_ai_agent_relationships`, `uc_ai_agent_executions`
- Implement `uc_ai_agents_api` package spec
- Basic agent CRUD operations
- Agent type = 'profile' (wrapper around existing prompt profiles)

### Phase 2: Workflow Patterns (Weeks 3-5)
- Implement sequential workflow execution
- Implement conditional workflow execution
- Implement parallel workflow execution (using DBMS_SCHEDULER)
- Implement loop workflow execution
- Input/output mapping system
- Error handling and retry logic

### Phase 3: Orchestrator Pattern (Week 6-7)
- Dynamic tool registration from agents
- Orchestrator execution engine
- Delegation tracking and synthesis
- Testing with multiple delegate agents

### Phase 4: Handoff Pattern (Week 8-9)
- Handoff decision mechanism (structured output)
- Conversation history management
- Context passing between agents
- Handoff validation and error handling

### Phase 5: Conversation Pattern (Week 10-11)
- Round-robin implementation
- AI-driven moderator implementation
- Completion criteria evaluation
- Turn limit and timeout handling

### Phase 6: Polish & Documentation (Week 12)
- Performance optimization
- Comprehensive error handling
- API documentation
- Example implementations
- Migration guide from prompt profiles

---

## Usage Examples

### Example 1: Sequential Workflow
```sql
-- Analyze customer support ticket through multiple stages
DECLARE
  l_workflow_id NUMBER;
  l_result JSON_OBJECT_T;
  l_input JSON_OBJECT_T := JSON_OBJECT_T();
BEGIN
  -- Create the workflow
  l_workflow_id := uc_ai_agents_api.create_sequential_workflow(
    p_code => 'ticket_analysis_pipeline',
    p_description => 'Multi-stage ticket analysis',
    p_agent_steps => JSON_ARRAY_T('["classify_ticket", "extract_entities", "suggest_resolution"]')
  );
  
  -- Execute
  l_input.put('ticket_text', 'Customer cannot log in, getting error 403');
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code => 'ticket_analysis_pipeline',
    p_input_parameters => l_input
  );
  
  DBMS_OUTPUT.PUT_LINE('Category: ' || l_result.get_string('category'));
  DBMS_OUTPUT.PUT_LINE('Resolution: ' || l_result.get_string('suggested_resolution'));
END;
/
```

### Example 2: Orchestrator Pattern
```sql
-- Research assistant that delegates to specialized experts
DECLARE
  l_orchestrator_id NUMBER;
  l_result JSON_OBJECT_T;
  l_input JSON_OBJECT_T := JSON_OBJECT_T();
BEGIN
  -- Create orchestrator
  l_orchestrator_id := uc_ai_agents_api.create_agent(
    p_code => 'research_coordinator',
    p_agent_type => 'orchestrator',
    p_orchestration_config => '{
      "orchestrator_profile_code": "research_coordinator_prompt",
      "delegate_agents": [
        {
          "agent_code": "literature_reviewer",
          "tool_name": "search_academic_literature"
        },
        {
          "agent_code": "data_analyst",
          "tool_name": "analyze_datasets"
        },
        {
          "agent_code": "statistician",
          "tool_name": "run_statistical_tests"
        }
      ],
      "synthesis_prompt": "Synthesize findings from all experts into a research summary."
    }'
  );
  
  -- Execute research task
  l_input.put('research_question', 'What is the correlation between X and Y?');
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code => 'research_coordinator',
    p_input_parameters => l_input
  );
  
  DBMS_OUTPUT.PUT_LINE('Research Summary: ' || l_result.get_clob('final_message'));
  DBMS_OUTPUT.PUT_LINE('Experts consulted: ' || l_result.get_number('tool_calls_count'));
END;
/
```

### Example 3: Handoff Pattern
```sql
-- Customer service bot that hands off to specialists
DECLARE
  l_handoff_agent_id NUMBER;
  l_result JSON_OBJECT_T;
  l_input JSON_OBJECT_T := JSON_OBJECT_T();
BEGIN
  l_handoff_agent_id := uc_ai_agents_api.create_agent(
    p_code => 'customer_service_bot',
    p_agent_type => 'handoff',
    p_orchestration_config => '{
      "initial_agent_code": "general_support",
      "handoff_agents": [
        {"agent_code": "billing_specialist", "capabilities": ["billing", "refunds"]},
        {"agent_code": "technical_support", "capabilities": ["bugs", "errors"]}
      ],
      "max_handoffs": 2
    }'
  );
  
  l_input.put('customer_message', 'I was charged twice for my subscription');
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code => 'customer_service_bot',
    p_input_parameters => l_input
  );
  
  DBMS_OUTPUT.PUT_LINE('Final response: ' || l_result.get_clob('final_message'));
  DBMS_OUTPUT.PUT_LINE('Handoffs: ' || l_result.get_number('handoff_count'));
END;
/
```

### Example 4: Conversation Pattern (Round-Robin)
```sql
-- Software development team collaboration
DECLARE
  l_conversation_agent_id NUMBER;
  l_result JSON_OBJECT_T;
  l_input JSON_OBJECT_T := JSON_OBJECT_T();
BEGIN
  l_conversation_agent_id := uc_ai_agents_api.create_agent(
    p_code => 'dev_team_collaboration',
    p_agent_type => 'conversation',
    p_orchestration_config => '{
      "conversation_mode": "round_robin",
      "participant_agents": [
        {"agent_code": "architect", "role": "Design architecture"},
        {"agent_code": "developer", "role": "Write code"},
        {"agent_code": "tester", "role": "Test functionality"}
      ],
      "max_turns": 5
    }'
  );
  
  l_input.put('feature_request', 'Add user authentication with OAuth2');
  l_result := uc_ai_agents_api.execute_agent(
    p_agent_code => 'dev_team_collaboration',
    p_input_parameters => l_input
  );
  
  -- Get conversation transcript
  FOR turn IN (
    SELECT * FROM JSON_TABLE(
      l_result.get_clob('conversation'), '$[*]'
      COLUMNS (
        agent VARCHAR2(255) PATH '$.agent',
        message CLOB PATH '$.message'
      )
    )
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(turn.agent || ': ' || turn.message);
  END LOOP;
END;
/
```

---

## Key Design Decisions & Rationale

### 1. **Unified Agent Abstraction**
**Decision**: Single `uc_ai_agents` table with `agent_type` discriminator

**Rationale**: 
- Consistent API across all agent types
- Easier versioning and lifecycle management
- Simpler relationship tracking
- Reduces code duplication

**Alternative Considered**: Separate tables per agent type (rejected due to complexity)

### 2. **JSON-Based Configuration**
**Decision**: Store workflow and orchestration configs as JSON CLOBs

**Rationale**:
- Flexibility for complex configurations
- Schema evolution without ALTER TABLE
- Native JSON support in Oracle 12c+
- Easy to validate with JSON schemas

**Trade-off**: Less type safety than separate columns, but Oracle JSON constraints mitigate this

### 3. **Dynamic Tool Registration for Orchestrator**
**Decision**: Create temporary tools on-the-fly for delegate agents

**Rationale**:
- Avoids cluttering permanent tools table
- Allows orchestrator-specific tool customization
- Enables nested orchestration (orchestrator delegates to orchestrator)

**Alternative Considered**: Pre-register all agents as tools (rejected - too rigid and messy)

### 4. **Structured Output for Handoffs**
**Decision**: Use JSON schema to formalize handoff decisions

**Rationale**:
- Robust and parseable
- AI models natively support structured output
- Easy to validate and debug
- Consistent across providers

**Alternative Considered**: Parse natural language decisions (rejected - too error-prone)

### 5. **Workflow Composability**
**Decision**: Treat workflows as first-class agents

**Rationale**:
- Enables autonomous patterns to delegate to workflows
- Recursive composition (workflows containing workflows)
- Unified execution model
- Reusability across patterns

### 6. **Execution Context Persistence**
**Decision**: `uc_ai_agent_executions` table stores full execution state

**Rationale**:
- Debugging and auditing
- Resume failed executions
- Analytics on agent performance
- Session-based grouping for multi-turn interactions

### 7. **Oracle-Native Parallelism**
**Decision**: Use DBMS_PARALLEL_EXECUTE for parallel workflows

**Rationale**:
- Built-in synchronous waiting (`run_task` blocks until completion)
- Native retry support via `resume_task` for failed chunks
- Configurable parallelism level
- Proper resource management with chunk-based execution
- No need for polling or complex job tracking

**Alternative Considered**: DBMS_SCHEDULER (rejected - requires async polling for completion)

---

## Technical Considerations

### Performance
- **Index Strategy**: Add indexes on frequently queried columns (agent code, status, session_id)
- **JSON Performance**: Use Oracle JSON constraints and indexes for config validation
- **Parallel Execution**: Limit concurrent jobs to avoid resource exhaustion
- **Caching**: Consider caching agent definitions in package state for frequently executed agents

### Security
- **Authorization Schema**: Leverage existing tool authorization mechanism
- **Input Validation**: Validate all inputs against declared schemas
- **SQL Injection**: Use bind variables for dynamic SQL
- **Resource Limits**: Enforce timeout and max iteration limits

### Scalability
- **Execution History Cleanup**: Implement retention policy for `uc_ai_agent_executions`
- **Temporary Tool Cleanup**: Ensure dynamic tools are cleaned up even on error
- **Session Management**: Provide utilities to manage active sessions
- **Connection Pooling**: Reuse provider connections when possible

### Error Handling
- **Graceful Degradation**: Continue workflow on non-critical errors if configured
- **Retry Logic**: Implement exponential backoff for transient failures
- **Error Context**: Capture full context in execution history for debugging
- **Rollback Strategy**: Define savepoints for complex workflows

---

## Migration Path from Prompt Profiles

### Backward Compatibility
All existing prompt profiles remain functional. Users can:

1. **Continue using prompt profiles directly** via `uc_ai_prompt_profiles_api`
2. **Wrap prompt profiles as agents** for composition:
   ```sql
   l_agent_id := uc_ai_agents_api.create_agent(
     p_code => 'my_profile_agent',
     p_agent_type => 'profile',
     p_prompt_profile_code => 'my_existing_profile'  -- Uses latest active version
   );
   ```
3. **Gradually adopt agent patterns** as needed

### Migration Guide
```sql
-- Before: Simple prompt profile
l_result := uc_ai_prompt_profiles_api.execute_profile(
  p_code => 'text_classifier',
  p_parameters => l_params
);

-- After: Wrapped as agent (same result)
l_result := uc_ai_agents_api.execute_agent(
  p_agent_code => 'text_classifier',
  p_input_parameters => l_params
);

-- After: Composed in workflow
l_result := uc_ai_agents_api.execute_agent(
  p_agent_code => 'classification_pipeline',
  p_input_parameters => l_params
);
```

---

## Conclusion

This proposal provides a **comprehensive, Oracle-native solution** for multi-agent systems that:

✅ **Builds on existing infrastructure** (prompt profiles, tools, provider abstraction)  
✅ **Supports all requested patterns** (sequential, conditional, parallel, loop, orchestrator, handoff, conversation)  
✅ **Enables composition** (autonomous patterns can invoke workflow patterns)  
✅ **Remains easy to use** (declarative JSON config, simple API, migration path)  
✅ **Is technically robust** (execution history, error handling, schema validation, Oracle-native parallelism)

The phased implementation approach allows for **incremental delivery** and **early user feedback**. Starting with foundational components and workflow patterns provides immediate value while building toward the more complex autonomous patterns.

### Next Steps
1. **Review and feedback** on this proposal
2. **Prototype** Phase 1 (foundation) to validate table design
3. **Iterate** on API based on developer experience
4. **Document** with comprehensive examples and best practices
5. **Release** in stages with versioned agents

---

**Questions or Concerns?**
- How should we handle very long-running agents? (job queues vs inline execution)
- Should we support APEX integration hooks for UI progress indicators?
- Do we need a visual workflow builder, or is JSON config sufficient?
- Should agent versioning be independent or tied to prompt profile versions?

---

## Review Feedback

> **Review Status**: ✅ All items addressed (January 22, 2026)

### Resolved Items

| #   | Issue                                               | Resolution                                                                                                                      |
| --- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `prompt_profile_id` should be `prompt_profile_code` | ✅ Changed to `prompt_profile_code` + optional `prompt_profile_version`                                                          |
| 2   | `orchestrator_profile_id` in JSON config            | ✅ Changed to `orchestrator_profile_code` throughout                                                                             |
| 3   | DBMS_SCHEDULER permission issues                    | ✅ Switched to `DBMS_PARALLEL_EXECUTE` (built-in sync waiting + retry support)                                                   |
| 4   | Dynamic tool cleanup on error                       | ✅ Added exception handling with cleanup in EXCEPTION block                                                                      |
| 5   | Missing token/cost tracking                         | ✅ Added `total_input_tokens`, `total_output_tokens`, `total_cost_usd` to executions table                                       |
| 6   | Agent version in JSON unclear                       | ✅ Removed from JSON; all `agent_code` refs use latest active. Version stored as table column with status (like prompt_profiles) |
| 7   | Condition expression security                       | ✅ Using `APEX_PLUGIN_UTIL.GET_PLSQL_EXPR_RESULT_BOOLEAN` for safe PL/SQL evaluation with bind variables                         |
| 8   | Redundant relationships table                       | ✅ Removed table; JSON-only with validation on create/delete for referential integrity                                           |
| 9   | Missing FK constraint                               | ✅ N/A - using code reference instead of FK (prompt_profile_code)                                                                |
| 10  | execution_order validation                          | ✅ Will validate uniqueness/contiguity in `validate_workflow_definition`                                                         |
| 11  | get_agent return type                               | ✅ Kept as `%ROWTYPE` (acceptable)                                                                                               |
| 12  | Session ID generation                               | ✅ Added `generate_session_id` function using `SYS_GUID()`                                                                       |
| 13  | Conversation history size                           | ✅ Added `history_management` config with `sliding_window`, `summarize`, and `full` strategies                                   |

### Clarified Questions

| Question                                | Decision                                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------------ |
| Tool Inheritance (nested orchestrators) | Inner orchestrator starts fresh, does NOT inherit outer's tools                            |
| Cross-Version Agent Relationships       | References always use `agent_code` only → resolves to latest active version                |
| Async Execution Status                  | `DBMS_PARALLEL_EXECUTE.run_task` is synchronous (blocks until complete), no polling needed |
