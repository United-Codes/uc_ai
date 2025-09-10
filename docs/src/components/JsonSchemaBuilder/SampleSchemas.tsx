import type React from "react";
import { sampleSchemas } from "./samples";
import type { SampleSchema } from "./types";

interface SampleSchemasProps {
  onLoadSample: (sampleSchema: SampleSchema) => void;
  onOpenPasteModal: () => void;
}

const SampleSchemas: React.FC<SampleSchemasProps> = ({
  onLoadSample,
  onOpenPasteModal,
}) => {
  return (
    <div className="samples-section">
      <h3>Sample Schemas</h3>
      <p>Load pre-built schemas for common AI use cases or paste your own:</p>
      <div className="samples-grid">
        <button
          type="button"
          className="sample-card paste-card"
          onClick={onOpenPasteModal}
        >
          <h4>📋 Paste Schema</h4>
          <p>Paste an existing JSON schema to edit it</p>
        </button>
        {sampleSchemas.map((sample) => (
          <button
            key={sample.name}
            type="button"
            className="sample-card"
            onClick={() => onLoadSample(sample.schema)}
          >
            <h4>{sample.name}</h4>
            <p>{sample.description}</p>
          </button>
        ))}
      </div>
    </div>
  );
};

export default SampleSchemas;
