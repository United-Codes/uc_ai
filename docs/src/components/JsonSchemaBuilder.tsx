import React, { useState, useCallback, useId } from "react";
import SampleSchemas from "./JsonSchemaBuilder/SampleSchemas";
import PropertyItem from "./JsonSchemaBuilder/PropertyItem";
import PasteModal from "./JsonSchemaBuilder/PasteModal";
import {
  convertToSchemaProperties,
  convertJsonSchemaToProperties,
  generateJsonSchema,
  getAllPropertyIds,
} from "./JsonSchemaBuilder/utils";
import type {
  SchemaProperty,
  JsonSchema,
  SampleSchema,
} from "./JsonSchemaBuilder/types";
import "./JsonSchemaBuilder.css";

const JsonSchemaBuilder: React.FC = () => {
  const titleId = useId();
  const descriptionId = useId();

  const [schema, setSchema] = useState<JsonSchema>({
    $schema: "http://json-schema.org/draft-07/schema#",
    type: "object",
    title: "",
    description: "",
    properties: {},
    required: [],
  });

  const [properties, setProperties] = useState<SchemaProperty[]>([]);
  const [collapsedStates, setCollapsedStates] = useState<Map<string, boolean>>(
    new Map()
  );
  const [pasteText, setPasteText] = useState("");
  const [isPasteModalOpen, setIsPasteModalOpen] = useState(false);

  const openPasteModal = useCallback(() => {
    setIsPasteModalOpen(true);
  }, []);

  const closePasteModal = useCallback(() => {
    setIsPasteModalOpen(false);
  }, []);

  const toggleCollapse = useCallback((propertyId: string) => {
    setCollapsedStates((prev) => {
      const newStates = new Map(prev);
      newStates.set(propertyId, !newStates.get(propertyId));
      return newStates;
    });
  }, []);

  const expandAll = useCallback(() => {
    setCollapsedStates(new Map());
  }, []);

  const collapseAll = useCallback(() => {
    const allIds = getAllPropertyIds(properties);
    const newStates = new Map<string, boolean>();
    allIds.forEach((id) => {
      newStates.set(id, true);
    });
    setCollapsedStates(newStates);
  }, [properties]);

  const addProperty = useCallback(() => {
    const newProperty: SchemaProperty = {
      id: Date.now().toString(),
      name: "",
      type: "string",
      description: "",
      required: false,
    };
    setProperties((prev) => [...prev, newProperty]);
  }, []);

  const updateProperty = useCallback(
    (
      id: string,
      field: keyof SchemaProperty,
      value:
        | string
        | boolean
        | number
        | undefined
        | SchemaProperty
        | { type: string }
    ) => {
      setProperties((prev) =>
        prev.map((prop) =>
          prop.id === id ? { ...prop, [field]: value } : prop
        )
      );
    },
    []
  );

  const removeProperty = useCallback((id: string) => {
    setProperties((prev) => prev.filter((prop) => prop.id !== id));
  }, []);

  const addEnumValue = useCallback((propertyId: string, value: string) => {
    if (!value.trim()) return;
    setProperties((prev) =>
      prev.map((prop) =>
        prop.id === propertyId
          ? { ...prop, enum: [...(prop.enum || []), value] }
          : prop
      )
    );
  }, []);

  const removeEnumValue = useCallback((propertyId: string, index: number) => {
    setProperties((prev) =>
      prev.map((prop) =>
        prop.id === propertyId
          ? { ...prop, enum: prop.enum?.filter((_, i) => i !== index) }
          : prop
      )
    );
  }, []);

  const addNestedProperty = useCallback((parentId: string) => {
    const newProperty: SchemaProperty = {
      id: `${parentId}-${Date.now()}`,
      name: "",
      type: "string",
      description: "",
      required: false,
    };

    setProperties((prev) =>
      prev.map((prop) =>
        prop.id === parentId
          ? {
              ...prop,
              properties: [...(prop.properties || []), newProperty],
            }
          : prop
      )
    );
  }, []);

  const updateNestedProperty = useCallback(
    (
      parentId: string,
      childId: string,
      field: keyof SchemaProperty,
      value:
        | string
        | boolean
        | number
        | undefined
        | SchemaProperty
        | { type: string }
        | string[]
    ) => {
      setProperties((prev) =>
        prev.map((prop) =>
          prop.id === parentId
            ? {
                ...prop,
                properties:
                  prop.properties?.map((childProp) =>
                    childProp.id === childId
                      ? { ...childProp, [field]: value }
                      : childProp
                  ) || [],
              }
            : prop
        )
      );
    },
    []
  );

  const removeNestedProperty = useCallback(
    (parentId: string, childId: string) => {
      setProperties((prev) =>
        prev.map((prop) =>
          prop.id === parentId
            ? {
                ...prop,
                properties:
                  prop.properties?.filter(
                    (childProp) => childProp.id !== childId
                  ) || [],
              }
            : prop
        )
      );
    },
    []
  );

  const generateSchema = useCallback(() => {
    const generatedSchema = generateJsonSchema(
      properties,
      schema.title || "",
      schema.description || "",
      schema.$schema
    );
    setSchema(generatedSchema);
  }, [properties, schema.title, schema.description, schema.$schema]);

  const copyToClipboard = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(JSON.stringify(schema, null, 2));
      alert("Schema copied to clipboard!");
    } catch (err) {
      console.error("Failed to copy to clipboard:", err);
    }
  }, [schema]);

  const downloadSchema = useCallback(() => {
    const blob = new Blob([JSON.stringify(schema, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${schema.title || "schema"}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, [schema]);

  const loadSample = useCallback((sampleSchema: SampleSchema) => {
    setProperties([]);
    setCollapsedStates(new Map());

    setSchema((prev: JsonSchema) => ({
      ...prev,
      title: sampleSchema.title,
      description: sampleSchema.description,
    }));

    setProperties(convertToSchemaProperties(sampleSchema.properties));
  }, []);

  const parseAndLoadSchema = useCallback(
    (schemaText: string) => {
      try {
        const parsedSchema = JSON.parse(schemaText) as JsonSchema;

        if (!parsedSchema.type || !parsedSchema.properties) {
          throw new Error("Invalid JSON schema format");
        }

        setProperties([]);
        setCollapsedStates(new Map());

        setSchema({
          $schema:
            parsedSchema.$schema || "http://json-schema.org/draft-07/schema#",
          type: parsedSchema.type,
          title: parsedSchema.title || "",
          description: parsedSchema.description || "",
          properties: parsedSchema.properties,
          required: parsedSchema.required || [],
        });

        const convertedProperties = convertJsonSchemaToProperties(
          parsedSchema.properties,
          parsedSchema.required || []
        );

        setProperties(convertedProperties);
        closePasteModal();
        setPasteText("");
      } catch (error) {
        alert(
          `Error parsing schema: ${
            error instanceof Error ? error.message : "Invalid JSON"
          }`
        );
      }
    },
    [closePasteModal]
  );

  React.useEffect(() => {
    generateSchema();
  }, [generateSchema]);

  return (
    <div className="json-schema-builder not-content">
      <div className="schema-header">
        <h2>JSON Schema Builder</h2>
        <p>Create JSON schemas with an intuitive visual interface</p>
      </div>

      <SampleSchemas
        onLoadSample={loadSample}
        onOpenPasteModal={openPasteModal}
      />

      <div className="schema-metadata">
        <div className="form-row">
          <div className="form-group">
            <label htmlFor={titleId}>Schema Title</label>
            <input
              id={titleId}
              type="text"
              value={schema.title || ""}
              onChange={(e) =>
                setSchema((prev: JsonSchema) => ({
                  ...prev,
                  title: e.target.value,
                }))
              }
              placeholder="Enter schema title"
            />
          </div>

          <div className="form-group">
            <label htmlFor={descriptionId}>Schema Description</label>
            <textarea
              id={descriptionId}
              value={schema.description || ""}
              onChange={(e) =>
                setSchema((prev: JsonSchema) => ({
                  ...prev,
                  description: e.target.value,
                }))
              }
              placeholder="Enter schema description"
            />
          </div>
        </div>
      </div>

      <div>
        <div className="properties-header">
          <h3>Properties</h3>
          <div className="tree-controls">
            <button
              type="button"
              className="btn btn-small"
              onClick={expandAll}
              title="Expand all properties"
            >
              Expand All
            </button>
            <button
              type="button"
              className="btn btn-small"
              onClick={collapseAll}
              title="Collapse all properties"
            >
              Collapse All
            </button>
          </div>
        </div>

        {properties.map((property) => (
          <PropertyItem
            key={property.id}
            property={property}
            collapsedStates={collapsedStates}
            onToggleCollapse={toggleCollapse}
            onUpdateProperty={updateProperty}
            onRemoveProperty={removeProperty}
            onAddEnumValue={addEnumValue}
            onRemoveEnumValue={removeEnumValue}
            onAddNestedProperty={addNestedProperty}
            onUpdateNestedProperty={updateNestedProperty}
            onRemoveNestedProperty={removeNestedProperty}
          />
        ))}

        <button
          type="button"
          className="add-property-btn"
          onClick={addProperty}
        >
          + Add Property
        </button>
      </div>

      <div className="actions">
        <button
          type="button"
          className="btn btn-primary"
          onClick={copyToClipboard}
        >
          Copy Schema
        </button>
        <button type="button" className="btn" onClick={downloadSchema}>
          Download Schema
        </button>
      </div>

      <div className="preview-section">
        <h3>Generated JSON Schema</h3>
        <div className="schema-output">{JSON.stringify(schema, null, 2)}</div>
      </div>

      <PasteModal
        isOpen={isPasteModalOpen}
        onClose={closePasteModal}
        onLoadSchema={parseAndLoadSchema}
        pasteText={pasteText}
        setPasteText={setPasteText}
      />
    </div>
  );
};

export default JsonSchemaBuilder;
