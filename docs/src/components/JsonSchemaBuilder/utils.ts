import type {
  JsonSchema,
  JsonSchemaProperty,
  SchemaProperty,
  SampleProperty,
} from "./types";

export const convertToSchemaProperties = (
  props: SampleProperty[]
): SchemaProperty[] => {
  return props.map((prop) => {
    const converted: SchemaProperty = {
      id: prop.id,
      name: prop.name,
      type: prop.type,
      description: prop.description,
      required: prop.required,
    };

    if (prop.enum) {
      converted.enum = prop.enum;
    }

    if (prop.minimum !== undefined) {
      converted.minimum = prop.minimum;
    }

    if (prop.maximum !== undefined) {
      converted.maximum = prop.maximum;
    }

    if (prop.items) {
      converted.items = {
        id: `${prop.id}-item`,
        name: "item",
        type: prop.items.type,
        required: false,
      };
    }

    if (prop.properties) {
      converted.properties = convertToSchemaProperties(prop.properties);
    }

    return converted;
  });
};

export const convertJsonSchemaToProperties = (
  schemaProps: Record<string, JsonSchemaProperty>,
  requiredFields: string[] = []
): SchemaProperty[] => {
  return Object.entries(schemaProps).map(([name, prop], index) => {
    const id = `imported-${Date.now()}-${index}`;
    const converted: SchemaProperty = {
      id,
      name,
      type: prop.type,
      description: prop.description,
      required: requiredFields.includes(name),
    };

    if (prop.enum) {
      converted.enum = prop.enum;
    }

    if (prop.minimum !== undefined) {
      converted.minimum = prop.minimum;
    }

    if (prop.maximum !== undefined) {
      converted.maximum = prop.maximum;
    }

    if (prop.type === "array" && prop.items) {
      converted.items = {
        id: `${id}-item`,
        name: "item",
        type: prop.items.type,
        required: false,
      };
    }

    if (prop.type === "object" && prop.properties) {
      converted.properties = convertJsonSchemaToProperties(
        prop.properties,
        prop.required || []
      );
    }

    return converted;
  });
};

export const buildSchemaProperties = (
  props: SchemaProperty[]
): Record<string, JsonSchemaProperty> => {
  const schemaProperties: Record<string, JsonSchemaProperty> = {};

  props.forEach((prop) => {
    if (!prop.name) return;

    const propertySchema: JsonSchemaProperty = {
      type: prop.type,
      ...(prop.description && { description: prop.description }),
    };

    if (prop.type === "array" && prop.items) {
      propertySchema.items = {
        type: prop.items.type,
        ...(prop.items.description && {
          description: prop.items.description,
        }),
      };
    }

    if (
      prop.type === "object" &&
      prop.properties &&
      prop.properties.length > 0
    ) {
      propertySchema.properties = buildSchemaProperties(prop.properties);
      const nestedRequired = prop.properties
        .filter((child) => child.required && child.name)
        .map((child) => child.name);
      if (nestedRequired.length > 0) {
        propertySchema.required = nestedRequired;
      }
    }

    if (prop.enum && prop.enum.length > 0) {
      propertySchema.enum = prop.enum;
    }

    if (prop.type === "number" || prop.type === "integer") {
      if (prop.minimum !== undefined) {
        propertySchema.minimum = prop.minimum;
      }
      if (prop.maximum !== undefined) {
        propertySchema.maximum = prop.maximum;
      }
    }

    schemaProperties[prop.name] = propertySchema;
  });

  return schemaProperties;
};

export const generateJsonSchema = (
  properties: SchemaProperty[],
  title: string,
  description: string,
  schemaVersion: string
): JsonSchema => {
  const schemaProperties = buildSchemaProperties(properties);
  const required: string[] = properties
    .filter((prop) => prop.required && prop.name)
    .map((prop) => prop.name);

  return {
    $schema: schemaVersion,
    type: "object",
    ...(title && { title }),
    ...(description && { description }),
    properties: schemaProperties,
    ...(required.length > 0 && { required }),
  };
};

export const getAllPropertyIds = (props: SchemaProperty[]): string[] => {
  const ids: string[] = [];
  props.forEach((prop) => {
    if (prop.type === "object" && prop.properties) {
      ids.push(prop.id);
      ids.push(...getAllPropertyIds(prop.properties));
    }
  });
  return ids;
};
