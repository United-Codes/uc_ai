import type { SampleSchema } from "./types";

export const sampleSchemas: Array<{
  name: string;
  description: string;
  schema: SampleSchema;
}> = [
  {
    name: "Simple AI Response",
    description: "Basic structured response for AI tools",
    schema: {
      title: "Simple AI Response",
      description:
        "A basic response format for AI tools that return text with a confidence score",
      properties: [
        {
          id: "1",
          name: "response",
          type: "string",
          description: "The generated response text",
          required: true,
        },
        {
          id: "2",
          name: "confidence",
          type: "number",
          description: "Confidence score between 0 and 1",
          required: true,
          minimum: 0,
          maximum: 1,
        },
      ],
    },
  },
  {
    name: "Weather Tool",
    description: "Tool for getting weather information",
    schema: {
      title: "Weather Information Tool",
      description: "Schema for a weather information retrieval tool",
      properties: [
        {
          id: "1",
          name: "location",
          type: "string",
          description: "The city and country for weather lookup",
          required: true,
        },
        {
          id: "2",
          name: "unit",
          type: "string",
          description: "Temperature unit preference",
          required: false,
          enum: ["celsius", "fahrenheit", "kelvin"],
        },
        {
          id: "3",
          name: "include_forecast",
          type: "boolean",
          description: "Whether to include 5-day forecast",
          required: false,
        },
      ],
    },
  },
  {
    name: "Analysis Result",
    description: "Complex analysis response with multiple data types",
    schema: {
      title: "Data Analysis Result",
      description: "Structured response for data analysis tasks",
      properties: [
        {
          id: "1",
          name: "summary",
          type: "string",
          description: "Executive summary of the analysis",
          required: true,
        },
        {
          id: "2",
          name: "metrics",
          type: "object",
          description: "Key performance metrics",
          required: true,
          properties: [
            {
              id: "2-1",
              name: "accuracy",
              type: "number",
              description: "Analysis accuracy score",
              required: true,
            },
            {
              id: "2-2",
              name: "sample_size",
              type: "integer",
              description: "Number of data points analyzed",
              required: true,
            },
          ],
        },
        {
          id: "3",
          name: "insights",
          type: "array",
          description: "List of key insights discovered",
          required: true,
          items: { type: "string" },
        },
        {
          id: "4",
          name: "recommendations",
          type: "array",
          description: "Actionable recommendations",
          required: false,
          items: { type: "string" },
        },
      ],
    },
  },
  {
    name: "Advanced AI Tool",
    description: "Comprehensive tool schema with validation and metadata",
    schema: {
      title: "Advanced Content Generation Tool",
      description:
        "Schema for an advanced AI content generation tool with multiple output formats and validation",
      properties: [
        {
          id: "1",
          name: "content_type",
          type: "string",
          description: "Type of content to generate",
          required: true,
          enum: ["article", "summary", "email", "report", "social_post"],
        },
        {
          id: "2",
          name: "parameters",
          type: "object",
          description: "Generation parameters",
          required: true,
          properties: [
            {
              id: "2-1",
              name: "topic",
              type: "string",
              description: "Main topic or subject",
              required: true,
            },
            {
              id: "2-2",
              name: "tone",
              type: "string",
              description: "Writing tone",
              required: false,
              enum: [
                "professional",
                "casual",
                "formal",
                "conversational",
                "persuasive",
              ],
            },
            {
              id: "2-3",
              name: "target_audience",
              type: "string",
              description: "Intended audience",
              required: false,
            },
            {
              id: "2-4",
              name: "word_count",
              type: "object",
              description: "Word count constraints",
              required: false,
              properties: [
                {
                  id: "2-4-1",
                  name: "min",
                  type: "integer",
                  description: "Minimum word count",
                  required: false,
                },
                {
                  id: "2-4-2",
                  name: "max",
                  type: "integer",
                  description: "Maximum word count",
                  required: false,
                },
              ],
            },
          ],
        },
        {
          id: "3",
          name: "output_format",
          type: "object",
          description: "Desired output format specifications",
          required: false,
          properties: [
            {
              id: "3-1",
              name: "format",
              type: "string",
              description: "Output format type",
              required: true,
              enum: ["markdown", "html", "plain_text", "json"],
            },
            {
              id: "3-2",
              name: "include_metadata",
              type: "boolean",
              description: "Whether to include generation metadata",
              required: false,
            },
            {
              id: "3-3",
              name: "sections",
              type: "array",
              description: "Required sections in the output",
              required: false,
              items: { type: "string" },
            },
          ],
        },
        {
          id: "4",
          name: "validation_rules",
          type: "array",
          description: "Content validation rules to apply",
          required: false,
          items: { type: "string" },
        },
      ],
    },
  },
];
