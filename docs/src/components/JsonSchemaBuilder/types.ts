export interface SchemaProperty {
  id: string;
  name: string;
  type: string;
  description?: string;
  required: boolean;
  enum?: string[];
  minimum?: number;
  maximum?: number;
  items?: SchemaProperty;
  properties?: SchemaProperty[];
  collapsed?: boolean;
}

export interface JsonSchemaProperty {
  type: string;
  description?: string;
  enum?: string[];
  minimum?: number;
  maximum?: number;
  items?: {
    type: string;
    description?: string;
    properties?: Record<string, JsonSchemaProperty>;
    required?: string[];
  };
  properties?: Record<string, JsonSchemaProperty>;
  required?: string[];
}

export interface SampleProperty {
  id: string;
  name: string;
  type: string;
  description?: string;
  required: boolean;
  enum?: string[];
  minimum?: number;
  maximum?: number;
  items?: { type: string };
  properties?: SampleProperty[];
}

export interface SampleSchema {
  title: string;
  description: string;
  properties: SampleProperty[];
}

export interface JsonSchema {
  $schema: string;
  type: string;
  title?: string;
  description?: string;
  properties: Record<string, JsonSchemaProperty>;
  required?: string[];
}
