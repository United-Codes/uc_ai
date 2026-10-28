"""A partner client for the A2A endpoint of the service desk, built on the official a2a-sdk.

Install:  pip install a2a-sdk httpx
Run:      python -I svc_client.py --base <endpoint URL> "question 1" "question 2"

The base URL is the endpoint without a route, for example
https://api.example.com/ords/demo/a2a/service-desk. The API key comes from the
environment variable A2A_API_KEY (or --key). Do not write a key into this file.
Every question after the first one continues the same conversation, because the
script sends the contextId of the first task with it.

--insecure    do not check the TLS certificate. Use it only for a development
              database with a self-signed certificate.
--background  send each question with returnImmediately and poll GetTask until
              the task ends. The script prints the state at each poll.
"""

import argparse
import asyncio
import os
import sys
import time
import uuid

import httpx
from a2a.client import ClientConfig, create_client
from a2a.types import (
    GetTaskRequest,
    Message,
    Part,
    Role,
    SendMessageConfiguration,
    SendMessageRequest,
    TaskState,
)
from google.protobuf.json_format import MessageToDict

FINAL = (TaskState.TASK_STATE_COMPLETED, TaskState.TASK_STATE_FAILED, TaskState.TASK_STATE_CANCELED)


def artifact_text(task):
    return "\n".join(p.text for a in task.artifacts for p in a.parts if p.HasField("text"))


def show(task, seconds):
    usage = MessageToDict(task.metadata).get("usage", {})
    print(f"state:    {TaskState.Name(task.status.state)}")
    print(f"context:  {task.context_id}")
    print(f"seconds:  {seconds:.1f}")
    print(f"tokens:   {int(usage.get('inputTokens', 0))} in, {int(usage.get('outputTokens', 0))} out")
    print(artifact_text(task) or f"(no artifact; status message: {task.status.message})")


async def ask(client, text, context_id, background):
    config = SendMessageConfiguration(return_immediately=background) if background else None
    request = SendMessageRequest(
        message=Message(
            role=Role.ROLE_USER,
            message_id=str(uuid.uuid4()),
            context_id=context_id or "",
            parts=[Part(text=text)],
        ),
        configuration=config,
    )
    started = time.monotonic()
    task = None
    async for event in client.send_message(request):
        if event.HasField("task"):
            task = event.task
    if background:
        print(f"first answer after {time.monotonic() - started:.1f} s: {TaskState.Name(task.status.state)}")
        while task.status.state not in FINAL:
            await asyncio.sleep(2)
            task = await client.get_task(GetTaskRequest(id=task.id))
            print(f"  {time.monotonic() - started:5.1f} s  {TaskState.Name(task.status.state)}")
    return task, time.monotonic() - started


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("questions", nargs="+")
    parser.add_argument("--base", default=os.environ.get("A2A_BASE"))
    parser.add_argument("--key", default=os.environ.get("A2A_API_KEY"))
    parser.add_argument("--insecure", action="store_true")
    parser.add_argument("--background", action="store_true")
    args = parser.parse_args()
    if not args.base or not args.key:
        sys.exit("Give --base and --key, or set A2A_BASE and A2A_API_KEY.")

    async with httpx.AsyncClient(
        headers={"X-API-Key": args.key}, timeout=300, verify=not args.insecure
    ) as http:
        # create_client reads the agent card and picks a binding from it.
        client = await create_client(
            args.base, client_config=ClientConfig(streaming=False, httpx_client=http)
        )
        context_id = None
        for number, text in enumerate(args.questions, start=1):
            print(f"\n--- question {number}: {text}")
            task, seconds = await ask(client, text, context_id, args.background)
            show(task, seconds)
            context_id = task.context_id


asyncio.run(main())
