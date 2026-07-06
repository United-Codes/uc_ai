// @ts-check

import { unified } from "@astrojs/markdown-remark";
import react from "@astrojs/react";
import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightImageZoom from "starlight-image-zoom";
import starlightLinksValidator from "starlight-links-validator";

// https://astro.build/config
export default defineConfig({
	site: "https://united-codes.com/products/uc-ai/docs",
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
					label: "Guides",
					collapsed: false,
					items: [
						"guides/installation",
						"guides/quickstart",
						"guides/use-cases",
						"guides/providers",
						"guides/tools",
						"guides/file_analysis",
						"guides/reasoning",
						"guides/structured_output",
						"guides/prompt-profiles",
						"guides/toon",
						"guides/event-callbacks",
						"guides/agentic-ai",
						{
							label: "Multi-Agent Systems",
							badge: {
								text: "WIP",
								variant: "caution",
							},
							items: [
								{ autogenerate: { directory: "guides/multi-agent-systems" } },
							],
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
