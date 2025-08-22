import React, { useState, useCallback, useId } from "react";

interface SchemaProperty {
  id: string;
  name: string;
  type: string;
  description?: string;
  required: boolean;
  enum?: string[];
  items?: SchemaProperty;
  properties?: SchemaProperty[];
}

interface JsonSchemaProperty {
  type: string;
  description?: string;
  enum?: string[];
  items?: {
    type: string;
    description?: string;
    properties?: Record<string, JsonSchemaProperty>;
    required?: string[];
  };
  properties?: Record<string, JsonSchemaProperty>;
  required?: string[];
}

interface JsonSchema {
  $schema: string;
  type: string;
  title?: string;
  description?: string;
  properties: Record<string, JsonSchemaProperty>;
  required?: string[];
}

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
  const [showPreview, setShowPreview] = useState(false);

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
      value: string | boolean | SchemaProperty | { type: string }
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
      value: string | boolean | SchemaProperty | { type: string } | string[]
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
    const buildSchemaProperties = (
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

        schemaProperties[prop.name] = propertySchema;
      });

      return schemaProperties;
    };

    const schemaProperties = buildSchemaProperties(properties);
    const required: string[] = properties
      .filter((prop) => prop.required && prop.name)
      .map((prop) => prop.name);

    const generatedSchema: JsonSchema = {
      $schema: schema.$schema,
      type: "object",
      ...(schema.title && { title: schema.title }),
      ...(schema.description && { description: schema.description }),
      properties: schemaProperties,
      ...(required.length > 0 && { required }),
    };

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

  React.useEffect(() => {
    generateSchema();
  }, [generateSchema]);

  const renderNestedProperties = (
    parentProperty: SchemaProperty,
    parentId: string,
    depth: number = 0
  ) => {
    if (parentProperty.type !== "object" || !parentProperty.properties) {
      return null;
    }

    return (
      <>
        {parentProperty.properties.map((nestedProp) => {
          const nameId = `nested-name-${nestedProp.id}`;
          const typeId = `nested-type-${nestedProp.id}`;
          const descId = `nested-desc-${nestedProp.id}`;
          const requiredId = `nested-required-${nestedProp.id}`;

          return (
            <div key={nestedProp.id} className="property-item">
              <div className="property-header">
                <div className="form-group">
                  <label htmlFor={nameId}>Name</label>
                  <input
                    id={nameId}
                    type="text"
                    value={nestedProp.name}
                    onChange={(e) =>
                      updateNestedProperty(
                        parentId,
                        nestedProp.id,
                        "name",
                        e.target.value
                      )
                    }
                    placeholder="propertyName"
                  />
                </div>
                <div className="form-group">
                  <label htmlFor={typeId}>Type</label>
                  <select
                    id={typeId}
                    value={nestedProp.type}
                    onChange={(e) =>
                      updateNestedProperty(
                        parentId,
                        nestedProp.id,
                        "type",
                        e.target.value
                      )
                    }
                  >
                    <option value="string">String</option>
                    <option value="number">Number</option>
                    <option value="integer">Integer</option>
                    <option value="boolean">Boolean</option>
                    <option value="array">Array</option>
                    <option value="object">Object</option>
                    <option value="null">Null</option>
                  </select>
                </div>
                <div></div> {/* Spacer for grid alignment */}
                <div className="property-controls">
                  <div className="checkbox-wrapper">
                    <input
                      type="checkbox"
                      id={requiredId}
                      checked={nestedProp.required}
                      onChange={(e) =>
                        updateNestedProperty(
                          parentId,
                          nestedProp.id,
                          "required",
                          e.target.checked
                        )
                      }
                    />
                    <label htmlFor={requiredId}>Required</label>
                  </div>

                  <button
                    type="button"
                    className="remove-btn"
                    onClick={() =>
                      removeNestedProperty(parentId, nestedProp.id)
                    }
                    title="Remove property"
                  >
                    ✕
                  </button>
                </div>
              </div>

              <div className="property-body">
                <div className="form-group">
                  <label htmlFor={descId}>Description</label>
                  <input
                    id={descId}
                    type="text"
                    value={nestedProp.description || ""}
                    onChange={(e) =>
                      updateNestedProperty(
                        parentId,
                        nestedProp.id,
                        "description",
                        e.target.value
                      )
                    }
                    placeholder="Property description"
                  />
                </div>

                {/* Enum support for nested properties */}
                {(nestedProp.type === "string" ||
                  nestedProp.type === "number" ||
                  nestedProp.type === "integer") && (
                  <div className="enum-section">
                    <div className="enum-section-header">
                      Allowed Values (Optional)
                    </div>
                    {nestedProp.enum && nestedProp.enum.length > 0 && (
                      <div className="enum-values">
                        {nestedProp.enum.map((value, index) => (
                          <span
                            key={`${nestedProp.id}-enum-${value}-${index}`}
                            className="enum-tag"
                          >
                            {value}
                            <button
                              type="button"
                              onClick={() => {
                                const updatedEnum =
                                  nestedProp.enum?.filter(
                                    (_, i) => i !== index
                                  ) || [];
                                updateNestedProperty(
                                  parentId,
                                  nestedProp.id,
                                  "enum",
                                  updatedEnum
                                );
                              }}
                            >
                              ✕
                            </button>
                          </span>
                        ))}
                      </div>
                    )}
                    <div className="enum-input">
                      <input
                        type={nestedProp.type === "string" ? "text" : "number"}
                        placeholder="Add allowed value"
                        onKeyPress={(e) => {
                          if (e.key === "Enter") {
                            const value = e.currentTarget.value;
                            if (value.trim()) {
                              const updatedEnum = [
                                ...(nestedProp.enum || []),
                                value,
                              ];
                              updateNestedProperty(
                                parentId,
                                nestedProp.id,
                                "enum",
                                updatedEnum
                              );
                              e.currentTarget.value = "";
                            }
                          }
                        }}
                      />
                      <button
                        type="button"
                        className="btn btn-small"
                        onClick={(e) => {
                          const input = e.currentTarget
                            .previousElementSibling as HTMLInputElement;
                          const value = input.value;
                          if (value.trim()) {
                            const updatedEnum = [
                              ...(nestedProp.enum || []),
                              value,
                            ];
                            updateNestedProperty(
                              parentId,
                              nestedProp.id,
                              "enum",
                              updatedEnum
                            );
                            input.value = "";
                          }
                        }}
                      >
                        Add
                      </button>
                    </div>
                  </div>
                )}

                {/* Recursively render nested object properties */}
                {nestedProp.type === "object" && (
                  <div className="nested-section">
                    <div className="nested-header">
                      <span>Object Properties</span>
                      <button
                        type="button"
                        className="btn btn-small btn-primary"
                        onClick={() => addNestedProperty(nestedProp.id)}
                      >
                        + Add Property
                      </button>
                    </div>
                    <div className="nested-properties">
                      {renderNestedProperties(
                        nestedProp,
                        nestedProp.id,
                        depth + 1
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </>
    );
  };

  return (
    <div className="json-schema-builder">
      <style>{`
        .json-schema-builder {
          max-width: 1000px;
          margin: 0 auto;
          padding: 16px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          line-height: 1.4;
        }
        
        .schema-header {
          border-bottom: 1px solid #e5e7eb;
          padding-bottom: 16px;
          margin-bottom: 20px;
        }
        
        .schema-header h2 {
          margin: 0 0 4px 0;
          font-size: 20px;
          font-weight: 600;
          color: #111827;
        }
        
        .schema-header p {
          margin: 0 0 16px 0;
          font-size: 14px;
          color: #6b7280;
        }
        
        .form-row {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 12px;
          margin-bottom: 16px;
        }
        
        .form-group {
          margin-bottom: 12px;
        }
        
        .form-group label {
          display: block;
          margin-bottom: 4px;
          font-size: 13px;
          font-weight: 500;
          color: #374151;
        }
        
        .form-group input, .form-group textarea, .form-group select {
          width: 100%;
          padding: 6px 8px;
          border: 1px solid #d1d5db;
          border-radius: 3px;
          font-size: 13px;
          background: white;
          transition: border-color 0.15s ease;
        }
        
        .form-group input:focus, .form-group textarea:focus, .form-group select:focus {
          outline: none;
          border-color: #3b82f6;
          box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.1);
        }
        
        .form-group textarea {
          resize: vertical;
          min-height: 50px;
        }
        
        .property-item {
          border: 1px solid #e5e7eb;
          border-radius: 4px;
          margin-bottom: 8px;
          background: white;
        }
        
        .property-item:hover {
          border-color: #d1d5db;
        }
        
        .property-header {
          display: grid;
          grid-template-columns: 1fr auto auto auto auto;
          gap: 8px;
          align-items: end;
          padding: 12px 12px 8px 12px;
          background: #f9fafb;
          border-bottom: 1px solid #e5e7eb;
        }
        
        .property-body {
          padding: 12px;
        }
        
        .property-controls {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        
        .checkbox-wrapper {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 12px;
          color: #6b7280;
          white-space: nowrap;
        }
        
        .checkbox-wrapper input[type="checkbox"] {
          margin: 0;
          width: auto;
        }
        
        .remove-btn {
          padding: 4px;
          background: none;
          border: none;
          color: #9ca3af;
          cursor: pointer;
          border-radius: 2px;
          font-size: 14px;
          line-height: 1;
        }
        
        .remove-btn:hover {
          background: #fef2f2;
          color: #dc2626;
        }
        
        .nested-section {
          border-top: 1px solid #f3f4f6;
          margin-top: 8px;
        }
        
        .nested-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 8px 12px;
          background: #f9fafb;
          font-size: 12px;
          font-weight: 500;
          color: #6b7280;
        }
        
        .nested-properties {
          padding: 8px;
          background: #fafbfc;
        }
        
        .nested-properties .property-item {
          margin-bottom: 6px;
        }
        
        .nested-properties .property-header {
          background: white;
        }
        
        .enum-section {
          margin-top: 8px;
          padding-top: 8px;
          border-top: 1px solid #f3f4f6;
        }
        
        .enum-section-header {
          font-size: 12px;
          font-weight: 500;
          color: #6b7280;
          margin-bottom: 6px;
        }
        
        .enum-values {
          display: flex;
          flex-wrap: wrap;
          gap: 4px;
          margin-bottom: 8px;
        }
        
        .enum-tag {
          background: #f3f4f6;
          padding: 2px 6px;
          border-radius: 2px;
          font-size: 11px;
          display: flex;
          align-items: center;
          gap: 4px;
          color: #374151;
        }
        
        .enum-tag button {
          background: none;
          border: none;
          color: #9ca3af;
          cursor: pointer;
          font-size: 10px;
          padding: 0;
          line-height: 1;
        }
        
        .enum-tag button:hover {
          color: #dc2626;
        }
        
        .enum-input {
          display: flex;
          gap: 6px;
          align-items: center;
        }
        
        .enum-input input {
          flex: 1;
          font-size: 12px;
          padding: 4px 6px;
        }
        
        .btn {
          padding: 6px 12px;
          border: 1px solid transparent;
          border-radius: 3px;
          cursor: pointer;
          font-size: 13px;
          font-weight: 500;
          transition: all 0.15s ease;
          background: white;
          color: #374151;
        }
        
        .btn:hover {
          background: #f9fafb;
        }
        
        .btn-primary {
          background: #3b82f6;
          color: white;
          border-color: #3b82f6;
        }
        
        .btn-primary:hover {
          background: #2563eb;
          border-color: #2563eb;
        }
        
        .btn-small {
          padding: 3px 8px;
          font-size: 11px;
        }
        
        .add-property-btn {
          margin: 16px 0;
          width: 100%;
          border: 1px dashed #d1d5db;
          background: white;
          color: #6b7280;
          padding: 12px;
          text-align: center;
        }
        
        .add-property-btn:hover {
          border-color: #3b82f6;
          background: #f8faff;
          color: #3b82f6;
        }
        
        .actions {
          display: flex;
          gap: 8px;
          margin: 20px 0;
          padding-top: 16px;
          border-top: 1px solid #e5e7eb;
        }
        
        .preview-section {
          margin-top: 24px;
        }
        
        .preview-section h3 {
          margin: 0 0 12px 0;
          font-size: 16px;
          font-weight: 600;
          color: #111827;
        }
        
        .schema-output {
          background: #f8f9fa;
          border: 1px solid #e5e7eb;
          padding: 12px;
          border-radius: 4px;
          overflow-x: auto;
          font-family: 'SF Mono', 'Monaco', 'Cascadia Code', 'Roboto Mono', monospace;
          font-size: 12px;
          line-height: 1.4;
          white-space: pre;
          color: #374151;
        }
        
        @media (max-width: 768px) {
          .form-row {
            grid-template-columns: 1fr;
          }
          
          .property-header {
            grid-template-columns: 1fr;
            gap: 8px;
          }
          
          .property-controls {
            justify-content: space-between;
          }
          
          .actions {
            flex-direction: column;
          }
        }
      `}</style>

      <div className="schema-header">
        <h2>JSON Schema Builder</h2>
        <p>Create JSON schemas with an intuitive visual interface</p>

        <div className="form-row">
          <div className="form-group">
            <label htmlFor={titleId}>Schema Title</label>
            <input
              id={titleId}
              type="text"
              value={schema.title || ""}
              onChange={(e) =>
                setSchema((prev) => ({ ...prev, title: e.target.value }))
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
                setSchema((prev) => ({ ...prev, description: e.target.value }))
              }
              placeholder="Enter schema description"
            />
          </div>
        </div>
      </div>

      <div>
        <h3>Properties</h3>

        {properties.map((property) => {
          const nameId = `name-${property.id}`;
          const typeId = `type-${property.id}`;
          const descId = `desc-${property.id}`;
          const arrayTypeId = `array-type-${property.id}`;
          const requiredId = `required-${property.id}`;

          return (
            <div key={property.id} className="property-item">
              <div className="property-header">
                <div className="form-group">
                  <label htmlFor={nameId}>Name</label>
                  <input
                    id={nameId}
                    type="text"
                    value={property.name}
                    onChange={(e) =>
                      updateProperty(property.id, "name", e.target.value)
                    }
                    placeholder="propertyName"
                  />
                </div>

                <div className="form-group">
                  <label htmlFor={typeId}>Type</label>
                  <select
                    id={typeId}
                    value={property.type}
                    onChange={(e) =>
                      updateProperty(property.id, "type", e.target.value)
                    }
                  >
                    <option value="string">String</option>
                    <option value="number">Number</option>
                    <option value="integer">Integer</option>
                    <option value="boolean">Boolean</option>
                    <option value="array">Array</option>
                    <option value="object">Object</option>
                    <option value="null">Null</option>
                  </select>
                </div>

                {property.type === "array" && (
                  <div className="form-group">
                    <label htmlFor={arrayTypeId}>Item Type</label>
                    <select
                      id={arrayTypeId}
                      value={property.items?.type || "string"}
                      onChange={(e) =>
                        updateProperty(property.id, "items", {
                          type: e.target.value,
                        })
                      }
                    >
                      <option value="string">String</option>
                      <option value="number">Number</option>
                      <option value="integer">Integer</option>
                      <option value="boolean">Boolean</option>
                      <option value="object">Object</option>
                    </select>
                  </div>
                )}

                <div className="property-controls">
                  <div className="checkbox-wrapper">
                    <input
                      type="checkbox"
                      id={requiredId}
                      checked={property.required}
                      onChange={(e) =>
                        updateProperty(
                          property.id,
                          "required",
                          e.target.checked
                        )
                      }
                    />
                    <label htmlFor={requiredId}>Required</label>
                  </div>

                  <button
                    type="button"
                    className="remove-btn"
                    onClick={() => removeProperty(property.id)}
                    title="Remove property"
                  >
                    ✕
                  </button>
                </div>
              </div>

              <div className="property-body">
                <div className="form-group">
                  <label htmlFor={descId}>Description</label>
                  <input
                    id={descId}
                    type="text"
                    value={property.description || ""}
                    onChange={(e) =>
                      updateProperty(property.id, "description", e.target.value)
                    }
                    placeholder="Property description"
                  />
                </div>

                {/* Object Properties Section */}
                {property.type === "object" && (
                  <div className="nested-section">
                    <div className="nested-header">
                      <span>Object Properties</span>
                      <button
                        type="button"
                        className="btn btn-small btn-primary"
                        onClick={() => addNestedProperty(property.id)}
                      >
                        + Add Property
                      </button>
                    </div>
                    <div className="nested-properties">
                      {renderNestedProperties(property, property.id)}
                    </div>
                  </div>
                )}

                {(property.type === "string" ||
                  property.type === "number" ||
                  property.type === "integer") && (
                  <div className="enum-section">
                    <div className="enum-section-header">
                      Allowed Values (Optional)
                    </div>
                    {property.enum && property.enum.length > 0 && (
                      <div className="enum-values">
                        {property.enum.map((value, index) => (
                          <span
                            key={`${property.id}-enum-${value}-${index}`}
                            className="enum-tag"
                          >
                            {value}
                            <button
                              type="button"
                              onClick={() =>
                                removeEnumValue(property.id, index)
                              }
                            >
                              ✕
                            </button>
                          </span>
                        ))}
                      </div>
                    )}
                    <div className="enum-input">
                      <input
                        type={property.type === "string" ? "text" : "number"}
                        placeholder="Add allowed value"
                        onKeyPress={(e) => {
                          if (e.key === "Enter") {
                            addEnumValue(property.id, e.currentTarget.value);
                            e.currentTarget.value = "";
                          }
                        }}
                      />
                      <button
                        type="button"
                        className="btn btn-small"
                        onClick={(e) => {
                          const input = e.currentTarget
                            .previousElementSibling as HTMLInputElement;
                          addEnumValue(property.id, input.value);
                          input.value = "";
                        }}
                      >
                        Add
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          );
        })}

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
          onClick={() => setShowPreview(!showPreview)}
        >
          {showPreview ? "Hide Preview" : "Show Preview"}
        </button>
        <button type="button" className="btn" onClick={copyToClipboard}>
          Copy Schema
        </button>
        <button type="button" className="btn" onClick={downloadSchema}>
          Download Schema
        </button>
      </div>

      {showPreview && (
        <div className="preview-section">
          <h3>Generated JSON Schema</h3>
          <div className="schema-output">{JSON.stringify(schema, null, 2)}</div>
        </div>
      )}
    </div>
  );
};

export default JsonSchemaBuilder;
