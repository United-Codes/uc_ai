// @ts-check

import { unified } from "@astrojs/markdown-remark";
import react from "@astrojs/react";
import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightImageZoom from "starlight-image-zoom";
import starlightLinksValidator from "starlight-links-validator";

// https://astro.build/config
export default defineConfig({
	site: "https://www.united-codes.com/products/uc-ai/docs",
	base: "/products/uc-ai/docs",
	// Astro 7 defaults to the new "Satteri" Markdown processor, which
	// starlight-image-zoom does not support yet. Use the classic unified()
	// (remark/rehype) processor until the plugin catches up.
	markdown: {
		processor: unified(),
	},
	integrations: [
		starlight({
			title: "UC AI",
			logo: {
				src: "./src/assets/logo/logo-horizontal-primary-dark.svg",
			},
			social: [
				{
					icon: "github",
					label: "GitHub",
					href: "https://github.com/United-Codes/uc_ai",
				},
				{
					icon: "linkedin",
					label: "LinkedIn",
					href: "https://www.linkedin.com/company/united-codes/",
				},
				{
					icon: "x.com",
					label: "X/Twitter",
					href: "https://x.com/united_codes",
				},
				{
					icon: "blueSky",
					label: "Bluesky",
					href: "https://bsky.app/profile/united-codes.com",
				},
				{
					icon: "youtube",
					label: "YouTube",
					href: "https://www.youtube.com/@united-codes",
				},
			],
			sidebar: [
				{
					label: "UC AI",
					items: ["index"],
				},
				{
					// ONE menu entry for everything: tutorial/index.mdx lists the
					// tutorials, and each one links straight to its lesson 1. The
					// lessons themselves never appear in the menu, so a nine-lesson
					// course does not flood it. A new tutorial is a new directory
					// under tutorial/ plus a card on that index page — no config
					// change at all.
					label: "Tutorials",
					collapsed: false,
					badge: {
						text: "New",
						variant: "success",
					},
					items: ["tutorial"],
				},
				{
					label: "Guides",
					collapsed: false,
					// The groups only shape the menu. The files stay flat in
					// guides/, so no URL changes when a page moves between groups.
					items: [
						{
							label: "Getting Started",
							items: [
								"guides/installation",
								"guides/network-setup",
								"guides/quickstart",
								"guides/use-cases",
								"guides/providers",
							],
						},
						{
							label: "Core Features",
							items: [
								"guides/tools",
								"guides/programmatic-tool-calling",
								"guides/file_analysis",
								"guides/reasoning",
								"guides/structured_output",
								"guides/prompt-profiles",
								"guides/toon",
								"guides/event-callbacks",
							],
						},
						{
							label: "Agents",
							collapsed: true,
							items: [
								"guides/agentic-ai",
								{
									label: "Multi-Agent Systems",
									collapsed: true,
									items: [
										{
											autogenerate: { directory: "guides/multi-agent-systems" },
										},
									],
								},
								"guides/agent-memory",
								"guides/execution-hooks",
							],
						},
						{
							label: "APEX Chat",
							collapsed: true,
							items: [
								"guides/apex-chat-plugin",
								"guides/chat-widgets",
								"guides/chat-widgets-custom-types",
							],
						},
						{
							label: "Guardrails",
							collapsed: true,
							badge: {
								text: "Pro",
								variant: "tip",
							},
							items: [{ autogenerate: { directory: "guides/guardrails" } }],
						},
					],
				},
				{
					label: "Provider Setup",
					items: [{ autogenerate: { directory: "providers" } }],
				},
				{
					label: "API Reference",
					items: [{ autogenerate: { directory: "api" } }],
				},
				{
					label: "Other",
					items: [{ autogenerate: { directory: "other" } }],
				},
			],
			customCss: ["./src/styles/uc.css"],
			components: {
				Footer: "./src/components/Footer.astro",
				Head: "./src/components/Head.astro",
				PageFrame: "./src/components/PageFrame.astro",
			},
			plugins: [
				starlightLinksValidator({ errorOnLocalLinks: false }),
				starlightImageZoom(),
			],
		}),
		react(),
	],
});
