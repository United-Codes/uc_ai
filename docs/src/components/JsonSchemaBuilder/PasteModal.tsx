import React, { useRef } from "react";

interface PasteModalProps {
  isOpen: boolean;
  onClose: () => void;
  onLoadSchema: (schemaText: string) => void;
  pasteText: string;
  setPasteText: (text: string) => void;
}

const PasteModal: React.FC<PasteModalProps> = ({
  isOpen,
  onClose,
  onLoadSchema,
  pasteText,
  setPasteText,
}) => {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const pasteModalTitleId = React.useId();

  React.useEffect(() => {
    if (isOpen) {
      dialogRef.current?.showModal();
    } else {
      dialogRef.current?.close();
    }
  }, [isOpen]);

  const handleLoadSchema = () => {
    onLoadSchema(pasteText);
  };

  return (
    <dialog
      ref={dialogRef}
      onClose={onClose}
      aria-labelledby={pasteModalTitleId}
      className="paste-modal"
    >
      <div className="modal-content">
        <div className="modal-header">
          <h3 id={pasteModalTitleId}>Paste JSON Schema</h3>
          <button
            type="button"
            className="modal-close"
            onClick={onClose}
            aria-label="Close modal"
          >
            ✕
          </button>
        </div>
        <div className="modal-body">
          <p>
            Paste your JSON schema below and click "Load Schema" to import it:
          </p>
          <textarea
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            placeholder="Paste your JSON schema here..."
            rows={10}
            className="paste-textarea"
            aria-label="JSON schema text input"
          />
        </div>
        <div className="modal-footer">
          <button type="button" className="btn" onClick={onClose}>
            Cancel
          </button>
          <button
            type="button"
            className="btn btn-primary"
            onClick={handleLoadSchema}
            disabled={!pasteText.trim()}
          >
            Load Schema
          </button>
        </div>
      </div>
    </dialog>
  );
};

export default PasteModal;
