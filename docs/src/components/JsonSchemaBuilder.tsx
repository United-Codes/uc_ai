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
      <div style={{ marginLeft: `${depth * 20}px`, marginTop: "15px" }}>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: "10px",
            marginBottom: "10px",
          }}
        >
          <strong>Object Properties:</strong>
          <button
            type="button"
            className="btn btn-small btn-primary"
            onClick={() => addNestedProperty(parentId)}
          >
            + Add Property
          </button>
        </div>

        {parentProperty.properties.map((nestedProp) => {
          const nameId = `nested-name-${nestedProp.id}`;
          const typeId = `nested-type-${nestedProp.id}`;
          const descId = `nested-desc-${nestedProp.id}`;
          const requiredId = `nested-required-${nestedProp.id}`;

          return (
            <div
              key={nestedProp.id}
              className="property-item"
              style={{ backgroundColor: "#f8f9fa", marginBottom: "10px" }}
            >
              <button
                type="button"
                className="btn btn-small btn-danger remove-btn"
                onClick={() => removeNestedProperty(parentId, nestedProp.id)}
              >
                ✕
              </button>

              <div className="property-header">
                <div className="form-group">
                  <label htmlFor={nameId}>Property Name *</label>
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
              </div>

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

              <div className="checkbox-group">
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

              {/* Enum support for nested properties */}
              {(nestedProp.type === "string" ||
                nestedProp.type === "number" ||
                nestedProp.type === "integer") && (
                <div className="enum-section">
                  <div>
                    <strong>Allowed Values (Optional)</strong>
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
                              // Remove enum value for nested property
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
                            style={{
                              background: "none",
                              border: "none",
                              color: "#dc2626",
                              cursor: "pointer",
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
                      className="btn btn-small btn-secondary"
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
              {renderNestedProperties(nestedProp, nestedProp.id, depth + 1)}
            </div>
          );
        })}
      </div>
    );
  };

  return (
    <div className="json-schema-builder">
      <style>{`
        .json-schema-builder {
          max-width: 1200px;
          margin: 0 auto;
          padding: 20px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        
        .schema-header {
          background: #f8f9fa;
          padding: 20px;
          border-radius: 8px;
          margin-bottom: 20px;
        }
        
        .form-group {
          margin-bottom: 15px;
        }
        
        .form-group label {
          display: block;
          margin-bottom: 5px;
          font-weight: 600;
          color: #333;
        }
        
        .form-group input, .form-group textarea, .form-group select {
          width: 100%;
          padding: 8px 12px;
          border: 1px solid #ddd;
          border-radius: 4px;
          font-size: 14px;
        }
        
        .form-group textarea {
          resize: vertical;
          min-height: 60px;
        }
        
        .property-item {
          background: #fff;
          border: 1px solid #e0e0e0;
          border-radius: 8px;
          padding: 20px;
          margin-bottom: 15px;
          position: relative;
        }
        
        .nested-property {
          background: #f8f9fa;
          border: 1px solid #e9ecef;
          margin-left: 20px;
          margin-top: 10px;
        }
        
        .nested-section {
          margin-top: 15px;
          padding-top: 15px;
          border-top: 1px solid #eee;
        }
        
        .nested-header {
          display: flex;
          align-items: center;
          gap: 10px;
          margin-bottom: 10px;
          font-weight: 600;
          color: #495057;
        }
        
        .property-header {
          display: flex;
          gap: 15px;
          margin-bottom: 15px;
          flex-wrap: wrap;
        }
        
        .property-header > div {
          flex: 1;
          min-width: 200px;
        }
        
        .checkbox-group {
          display: flex;
          align-items: center;
          gap: 8px;
          margin-top: 10px;
        }
        
        .checkbox-group input[type="checkbox"] {
          width: auto;
        }
        
        .enum-section {
          margin-top: 15px;
          padding-top: 15px;
          border-top: 1px solid #eee;
        }
        
        .enum-values {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-bottom: 10px;
        }
        
        .enum-tag {
          background: #e3f2fd;
          padding: 4px 8px;
          border-radius: 4px;
          font-size: 12px;
          display: flex;
          align-items: center;
          gap: 5px;
        }
        
        .enum-input {
          display: flex;
          gap: 8px;
        }
        
        .enum-input input {
          flex: 1;
        }
        
        .btn {
          padding: 8px 16px;
          border: none;
          border-radius: 4px;
          cursor: pointer;
          font-size: 14px;
          font-weight: 500;
          transition: background-color 0.2s;
        }
        
        .btn-primary {
          background: #2563eb;
          color: white;
        }
        
        .btn-primary:hover {
          background: #1d4ed8;
        }
        
        .btn-secondary {
          background: #6b7280;
          color: white;
        }
        
        .btn-secondary:hover {
          background: #4b5563;
        }
        
        .btn-danger {
          background: #dc2626;
          color: white;
        }
        
        .btn-danger:hover {
          background: #b91c1c;
        }
        
        .btn-small {
          padding: 4px 8px;
          font-size: 12px;
        }
        
        .remove-btn {
          position: absolute;
          top: 10px;
          right: 10px;
          background: #fee2e2;
          color: #dc2626;
          border: 1px solid #fecaca;
        }
        
        .remove-btn:hover {
          background: #fecaca;
        }
        
        .actions {
          display: flex;
          gap: 10px;
          margin: 20px 0;
          flex-wrap: wrap;
        }
        
        .preview-section {
          margin-top: 30px;
        }
        
        .schema-output {
          background: #1e1e1e;
          color: #d4d4d4;
          padding: 20px;
          border-radius: 8px;
          overflow-x: auto;
          font-family: 'Courier New', monospace;
          font-size: 14px;
          line-height: 1.5;
          white-space: pre;
        }
        
        .toggle-btn {
          background: #059669;
          color: white;
        }
        
        .toggle-btn:hover {
          background: #047857;
        }
        
        @media (max-width: 768px) {
          .property-header {
            flex-direction: column;
          }
          
          .property-header > div {
            min-width: auto;
          }
          
          .actions {
            flex-direction: column;
          }
          
          .btn {
            width: 100%;
          }
        }
      `}</style>

      <div className="schema-header">
        <h2>JSON Schema Builder</h2>
        <p>Create JSON schemas with an intuitive visual interface</p>

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
              <button
                type="button"
                className="btn btn-small btn-danger remove-btn"
                onClick={() => removeProperty(property.id)}
              >
                ✕
              </button>

              <div className="property-header">
                <div className="form-group">
                  <label htmlFor={nameId}>Property Name *</label>
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
              </div>

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

              <div className="checkbox-group">
                <input
                  type="checkbox"
                  id={requiredId}
                  checked={property.required}
                  onChange={(e) =>
                    updateProperty(property.id, "required", e.target.checked)
                  }
                />
                <label htmlFor={requiredId}>Required</label>
              </div>

              {property.type === "array" && (
                <div className="form-group">
                  <label htmlFor={arrayTypeId}>Array Item Type</label>
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

              {/* Object Properties Section */}
              {property.type === "object" && (
                <div className="nested-section">
                  <div className="nested-header">
                    <span>Object Properties:</span>
                    <button
                      type="button"
                      className="btn btn-small btn-primary"
                      onClick={() => addNestedProperty(property.id)}
                    >
                      + Add Property
                    </button>
                  </div>
                  {renderNestedProperties(property, property.id)}
                </div>
              )}

              {(property.type === "string" ||
                property.type === "number" ||
                property.type === "integer") && (
                <div className="enum-section">
                  <div>
                    <strong>Allowed Values (Optional)</strong>
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
                            onClick={() => removeEnumValue(property.id, index)}
                            style={{
                              background: "none",
                              border: "none",
                              color: "#dc2626",
                              cursor: "pointer",
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
                      className="btn btn-small btn-secondary"
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
          );
        })}

        <button type="button" className="btn btn-primary" onClick={addProperty}>
          + Add Property
        </button>
      </div>

      <div className="actions">
        <button
          type="button"
          className="btn toggle-btn"
          onClick={() => setShowPreview(!showPreview)}
        >
          {showPreview ? "Hide Preview" : "Show Preview"}
        </button>
        <button
          type="button"
          className="btn btn-primary"
          onClick={copyToClipboard}
        >
          Copy Schema
        </button>
        <button
          type="button"
          className="btn btn-secondary"
          onClick={downloadSchema}
        >
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
