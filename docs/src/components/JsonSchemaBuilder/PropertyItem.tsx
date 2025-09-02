import type React from "react";
import type { SchemaProperty } from "./types";

interface PropertyItemProps {
  property: SchemaProperty;
  collapsedStates: Map<string, boolean>;
  onToggleCollapse: (propertyId: string) => void;
  onUpdateProperty: (
    id: string,
    field: keyof SchemaProperty,
    value:
      | string
      | boolean
      | number
      | undefined
      | SchemaProperty
      | { type: string }
  ) => void;
  onRemoveProperty: (id: string) => void;
  onAddEnumValue: (propertyId: string, value: string) => void;
  onRemoveEnumValue: (propertyId: string, index: number) => void;
  onAddNestedProperty: (parentId: string) => void;
  onUpdateNestedProperty: (
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
  ) => void;
  onRemoveNestedProperty: (parentId: string, childId: string) => void;
  depth?: number;
  isNested?: boolean;
  parentId?: string;
}

const PropertyItem: React.FC<PropertyItemProps> = ({
  property,
  collapsedStates,
  onToggleCollapse,
  onUpdateProperty,
  onRemoveProperty,
  onAddEnumValue,
  onRemoveEnumValue,
  onAddNestedProperty,
  onUpdateNestedProperty,
  onRemoveNestedProperty,
  depth = 0,
  isNested = false,
  parentId,
}) => {
  const nameId = `${isNested ? "nested-" : ""}name-${property.id}`;
  const typeId = `${isNested ? "nested-" : ""}type-${property.id}`;
  const descId = `${isNested ? "nested-" : ""}desc-${property.id}`;
  const arrayTypeId = `${isNested ? "nested-" : ""}array-type-${property.id}`;
  const requiredId = `${isNested ? "nested-" : ""}required-${property.id}`;
  const isCollapsed = collapsedStates.get(property.id) || false;
  const hasNestedProperties =
    property.type === "object" &&
    property.properties &&
    property.properties.length > 0;

  const updateField = (
    field: keyof SchemaProperty,
    value:
      | string
      | boolean
      | number
      | undefined
      | SchemaProperty
      | { type: string }
  ) => {
    if (isNested && parentId && onUpdateNestedProperty) {
      onUpdateNestedProperty(parentId, property.id, field, value);
    } else {
      onUpdateProperty(property.id, field, value);
    }
  };

  const removeProperty = () => {
    if (isNested && parentId && onRemoveNestedProperty) {
      onRemoveNestedProperty(parentId, property.id);
    } else {
      onRemoveProperty(property.id);
    }
  };

  const updateEnumValue = (index: number) => {
    if (isNested && parentId && onUpdateNestedProperty) {
      const updatedEnum = property.enum?.filter((_, i) => i !== index) || [];
      onUpdateNestedProperty(parentId, property.id, "enum", updatedEnum);
    } else {
      onRemoveEnumValue(property.id, index);
    }
  };

  const addEnumValue = (value: string) => {
    if (!value.trim()) return;
    if (isNested && parentId && onUpdateNestedProperty) {
      const updatedEnum = [...(property.enum || []), value];
      onUpdateNestedProperty(parentId, property.id, "enum", updatedEnum);
    } else {
      onAddEnumValue(property.id, value);
    }
  };

  const renderNestedProperties = (
    parentProperty: SchemaProperty,
    currentParentId: string,
    currentDepth: number = 0
  ) => {
    if (parentProperty.type !== "object" || !parentProperty.properties) {
      return null;
    }

    return (
      <>
        {parentProperty.properties.map((nestedProp) => (
          <PropertyItem
            key={nestedProp.id}
            property={nestedProp}
            collapsedStates={collapsedStates}
            onToggleCollapse={onToggleCollapse}
            onUpdateProperty={onUpdateProperty}
            onRemoveProperty={onRemoveProperty}
            onAddEnumValue={onAddEnumValue}
            onRemoveEnumValue={onRemoveEnumValue}
            onAddNestedProperty={onAddNestedProperty}
            onUpdateNestedProperty={onUpdateNestedProperty}
            onRemoveNestedProperty={onRemoveNestedProperty}
            depth={currentDepth + 1}
            isNested={true}
            parentId={currentParentId}
          />
        ))}
      </>
    );
  };

  return (
    <div
      className={`property-item ${isNested ? `depth-${depth}` : ""}`}
      style={isNested ? { marginLeft: `${depth * 20}px` } : {}}
    >
      <div className="property-header">
        <div className="property-name-section">
          {hasNestedProperties && (
            <button
              type="button"
              className="tree-toggle"
              onClick={() => onToggleCollapse(property.id)}
              aria-expanded={!isCollapsed}
              title={isCollapsed ? "Expand properties" : "Collapse properties"}
            >
              {isCollapsed ? "▶" : "▼"}
            </button>
          )}
          <div className="form-group">
            <label htmlFor={nameId}>Name</label>
            <input
              id={nameId}
              type="text"
              value={property.name}
              onChange={(e) => updateField("name", e.target.value)}
              placeholder="propertyName"
            />
          </div>
        </div>

        <div className="form-group">
          <label htmlFor={typeId}>Type</label>
          <select
            id={typeId}
            value={property.type}
            onChange={(e) => updateField("type", e.target.value)}
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

        {property.type === "array" ? (
          <div className="form-group">
            <label htmlFor={arrayTypeId}>Item Type</label>
            <select
              id={arrayTypeId}
              value={property.items?.type || "string"}
              onChange={(e) => updateField("items", { type: e.target.value })}
            >
              <option value="string">String</option>
              <option value="number">Number</option>
              <option value="integer">Integer</option>
              <option value="boolean">Boolean</option>
              <option value="object">Object</option>
            </select>
          </div>
        ) : (
          <div aria-hidden="true" />
        )}

        <div aria-hidden="true" />

        <div className="property-controls">
          <div className="checkbox-wrapper">
            <input
              type="checkbox"
              id={requiredId}
              checked={property.required}
              onChange={(e) => updateField("required", e.target.checked)}
            />
            <label htmlFor={requiredId}>Required</label>
          </div>

          <button
            type="button"
            className="remove-btn"
            onClick={removeProperty}
            title="Remove property"
          >
            ✕
          </button>
        </div>
      </div>

      {!isCollapsed && (
        <div className="property-body">
          <div className="form-group">
            <label htmlFor={descId}>Description</label>
            <input
              id={descId}
              type="text"
              value={property.description || ""}
              onChange={(e) => updateField("description", e.target.value)}
              placeholder="Property description"
            />
          </div>

          {(property.type === "string" ||
            property.type === "number" ||
            property.type === "integer") && (
            <div className="validation-section">
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
                          onClick={() => updateEnumValue(index)}
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
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        const value = e.currentTarget.value;
                        if (value.trim()) {
                          addEnumValue(value);
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
                        addEnumValue(value);
                        input.value = "";
                      }
                    }}
                  >
                    Add
                  </button>
                </div>
              </div>

              {(property.type === "number" || property.type === "integer") && (
                <div className="minmax-section">
                  <div className="enum-section-header">
                    Min/Max Values (Optional - alternative to allowed values)
                  </div>
                  <div className="minmax-inputs">
                    <div className="form-group">
                      <label
                        htmlFor={`${isNested ? "nested-" : ""}min-${
                          property.id
                        }`}
                      >
                        Minimum
                      </label>
                      <input
                        id={`${isNested ? "nested-" : ""}min-${property.id}`}
                        type="number"
                        value={property.minimum ?? ""}
                        onChange={(e) => {
                          const value =
                            e.target.value === ""
                              ? undefined
                              : Number(e.target.value);
                          updateField("minimum", value);
                        }}
                        placeholder="Min value"
                      />
                    </div>
                    <div className="form-group">
                      <label
                        htmlFor={`${isNested ? "nested-" : ""}max-${
                          property.id
                        }`}
                      >
                        Maximum
                      </label>
                      <input
                        id={`${isNested ? "nested-" : ""}max-${property.id}`}
                        type="number"
                        value={property.maximum ?? ""}
                        onChange={(e) => {
                          const value =
                            e.target.value === ""
                              ? undefined
                              : Number(e.target.value);
                          updateField("maximum", value);
                        }}
                        placeholder="Max value"
                      />
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}

          {property.type === "object" && (
            <div className="nested-section">
              <div className="nested-header">
                <span>Object Properties</span>
                <button
                  type="button"
                  className="btn btn-small btn-primary"
                  onClick={() => onAddNestedProperty(property.id)}
                >
                  + Add Property
                </button>
              </div>
              <div className="nested-properties">
                {renderNestedProperties(property, property.id, depth)}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default PropertyItem;
