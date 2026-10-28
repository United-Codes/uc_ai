"""Call the A2A endpoint of the service desk from Google ADK, an agent framework that knows nothing about UC AI.

Install:  pip install "google-adk[a2a]" httpx
Run:      python -I adk_client.py --base <endpoint URL> "question 1" "question 2"

ADK reads the agent card and wraps the remote agent as RemoteA2aAgent. This script
uses it as the root agent of an ADK runner. The runner needs no model key,
because the remote agent does the model work. Every question uses the same ADK
session, so ADK sends the same contextId and the desk continues the conversation.

The API key comes from the environment variable A2A_API_KEY (or --key). Do not
write a key into this file. --insecure turns off the TLS certificate check:
use it only for a development database with a self-signed certificate.
"""

import argparse
import asyncio
import os
import sys

import httpx
from google.adk.agents.remote_a2a_agent import RemoteA2aAgent
from google.adk.runners import InMemoryRunner
from google.genai import types


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("questions", nargs="+")
    parser.add_argument("--base", default=os.environ.get("A2A_BASE"))
    parser.add_argument("--key", default=os.environ.get("A2A_API_KEY"))
    parser.add_argument("--insecure", action="store_true")
    args = parser.parse_args()
    if not args.base or not args.key:
        sys.exit("Give --base and --key, or set A2A_BASE and A2A_API_KEY.")

    async with httpx.AsyncClient(
        headers={"X-API-Key": args.key}, timeout=300, verify=not args.insecure
    ) as http:
        agent = RemoteA2aAgent(
            name="service_desk",
            description="The partner service desk of a field-service company",
            agent_card=args.base.rstrip("/") + "/.well-known/agent-card.json",
            httpx_client=http,
        )
        runner = InMemoryRunner(agent=agent, app_name="partner")
        session = await runner.session_service.create_session(app_name="partner", user_id="robin")

        for number, text in enumerate(args.questions, start=1):
            print(f"\n--- question {number}: {text}")
            message = types.Content(role="user", parts=[types.Part(text=text)])
            async for event in runner.run_async(
                user_id="robin", session_id=session.id, new_message=message
            ):
                for part in (event.content.parts if event.content else []):
                    if part.text:
                        print(f"{event.author}: {part.text}")


asyncio.run(main())
