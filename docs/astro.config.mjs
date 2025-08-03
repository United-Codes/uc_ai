// @ts-check
import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightImageZoom from "starlight-image-zoom";
import starlightLinksValidator from "starlight-links-validator";

// https://astro.build/config
export default defineConfig({
	site: "https://united-codes.com/products/uc-ai/docs",
	base: "/products/uc-ai/docs",
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
					autogenerate: { directory: "guides" },
				},
				{
					label: "Providers",
					autogenerate: { directory: "providers" },
				},
				{
					label: "API Reference",
					autogenerate: { directory: "api" },
				},
				{
					label: "Other",
					autogenerate: { directory: "other" },
				},
			],
			customCss: ["./src/styles/uc.css"],
			components: {
				Footer: "./src/components/Footer.astro",
			},
			plugins: [
				starlightLinksValidator({ errorOnLocalLinks: false }),
				starlightImageZoom(),
			],
		}),
	],
});
