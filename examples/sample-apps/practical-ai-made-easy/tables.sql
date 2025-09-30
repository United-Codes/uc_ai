drop table if exists pame_settlement_demo;

create table pame_settlement_demo (
    settlement_id              number primary key,
    claim_number               varchar2(50 char) not null unique,
    policy_number              varchar2(50 char) not null,
    policy_type                varchar2(100 char), -- e.g., 'auto', 'homeowners', 'life'
    incident_date              date not null,
    incident_description       varchar2(500 char),
    claimant_first_name        varchar2(100 char) not null,
    claimant_last_name         varchar2(100 char) not null,
    claimant_email             varchar2(255 char),
    claimant_phone             varchar2(20 char),
    insured_first_name         varchar2(100 char),
    insured_last_name          varchar2(100 char),
    settlement_date            date not null,
    settlement_amount          number(18, 2) not null,
    currency_code              varchar2(3 char) default 'eur', -- assuming europe/euro as a default
    settlement_status          varchar2(50 char) not null, -- e.g., 'proposed', 'accepted', 'rejected', 'paid'
    release_signed_date        date,
    payment_due_date           date,
    payment_paid_date          date,
    negotiator_agent_name      varchar2(200 char),
    notes                      varchar2(1000 char),
    constraint pame_chk_settlement_amount check (settlement_amount >= 0),
    constraint pame_chk_settlement_date check (settlement_date >= incident_date),
    constraint pame_chk_payment_due_date check (payment_due_date >= settlement_date),
    constraint pame_chk_settlement_status CHECK (SETTLEMENT_STATUS IN ('Proposed', 'Accepted', 'Rejected', 'Paid'))
);

COMMENT ON TABLE pame_settlement_demo IS 'Un-normalized table for insurance settlement demo purposes.';
COMMENT ON COLUMN pame_settlement_demo.SETTLEMENT_ID IS 'Unique identifier for the settlement.';
COMMENT ON COLUMN pame_settlement_demo.CLAIM_NUMBER IS 'Unique identifier for the claim.';
COMMENT ON COLUMN pame_settlement_demo.POLICY_NUMBER IS 'Policy number associated with the claim.';
COMMENT ON COLUMN pame_settlement_demo.POLICY_TYPE IS 'Type of the insurance policy (e.g., Auto, Homeowners).';
COMMENT ON COLUMN pame_settlement_demo.INCIDENT_DATE IS 'Date of the incident that led to the claim.';
COMMENT ON COLUMN pame_settlement_demo.INCIDENT_DESCRIPTION IS 'Brief description of the incident.';
COMMENT ON COLUMN pame_settlement_demo.CLAIMANT_FIRST_NAME IS 'First name of the primary claimant.';
COMMENT ON COLUMN pame_settlement_demo.CLAIMANT_LAST_NAME IS 'Last name of the primary claimant.';
COMMENT ON COLUMN pame_settlement_demo.CLAIMANT_EMAIL IS 'Email address of the primary claimant.';
COMMENT ON COLUMN pame_settlement_demo.CLAIMANT_PHONE IS 'Phone number of the primary claimant.';
COMMENT ON COLUMN pame_settlement_demo.INSURED_FIRST_NAME IS 'First name of the insured person (if different from claimant).';
COMMENT ON COLUMN pame_settlement_demo.INSURED_LAST_NAME IS 'Last name of the insured person.';
COMMENT ON COLUMN pame_settlement_demo.SETTLEMENT_DATE IS 'Date the settlement was agreed upon/proposed.';
COMMENT ON COLUMN pame_settlement_demo.SETTLEMENT_AMOUNT IS 'Agreed-upon monetary amount of the settlement.';
COMMENT ON COLUMN pame_settlement_demo.CURRENCY_CODE IS 'Currency of the settlement amount (e.g., EUR, USD).';
COMMENT ON COLUMN pame_settlement_demo.SETTLEMENT_STATUS IS 'Current status of the settlement (e.g., Proposed, Accepted, Paid).';
COMMENT ON COLUMN pame_settlement_demo.RELEASE_SIGNED_DATE IS 'Date the release of claims document was signed.';
COMMENT ON COLUMN pame_settlement_demo.PAYMENT_DUE_DATE IS 'Date the settlement payment is due.';
COMMENT ON COLUMN pame_settlement_demo.PAYMENT_PAID_DATE IS 'Date the settlement payment was actually made.';
COMMENT ON COLUMN pame_settlement_demo.NEGOTIATOR_AGENT_NAME IS 'Name of the insurance agent/negotiator handling the settlement.';
COMMENT ON COLUMN pame_settlement_demo.NOTES IS 'Any additional notes pertaining to the settlement.';

-- 1. Proposed Settlement - Auto Claim
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    claimant_phone, insured_first_name, insured_last_name, settlement_date,
    settlement_amount, currency_code, settlement_status, negotiator_agent_name, notes
) VALUES (
    101, 'CL2025-001-AUTO', 'POL-AX789', 'Auto', DATE '2025-01-15',
    'Minor fender bender on Main Street', 'Alice', 'Smith', 'alice.smith@example.com',
    '+33612345678', 'Bob', 'Smith', DATE '2025-02-01',
    1500.00, 'EUR', 'Proposed', 'Jean Dupont', 'Claimant reviewing offer.'
);

-- 2. Accepted Settlement - Homeowners Claim, Payment Due Soon
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    claimant_phone, insured_first_name, insured_last_name, settlement_date,
    settlement_amount, currency_code, settlement_status, release_signed_date,
    payment_due_date, negotiator_agent_name, notes
) VALUES (
    102, 'CL2025-002-HOME', 'POL-HMB123', 'Homeowners', DATE '2025-03-01',
    'Roof damage from storm', 'Charles', 'Lefevre', 'charles.lefevre@example.com',
    '+491701234567', 'Charles', 'Lefevre', DATE '2025-04-05',
    7500.50, 'EUR', 'Accepted', DATE '2025-04-08',
    DATE '2025-04-20', 'Maria Schmidt', 'Release signed, awaiting payment processing.'
);

-- 3. Paid Settlement - Life Insurance Claim
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    claimant_phone, insured_first_name, insured_last_name, settlement_date,
    settlement_amount, currency_code, settlement_status, release_signed_date,
    payment_due_date, payment_paid_date, negotiator_agent_name, notes
) VALUES (
    103, 'CL2025-003-LIFE', 'POL-LIF987', 'Life', DATE '2025-01-10', -- Incident date prior to policy purchase for demo
    'Death of policyholder', 'Eva', 'Braun', 'eva.braun@example.com',
    '+447911123456', 'Franz', 'Braun', DATE '2025-03-15',
    100000.00, 'EUR', 'Paid', DATE '2025-03-20',
    DATE '2025-03-25', DATE '2025-03-24', 'David Miller', 'Beneficiary confirmed receipt of funds.'
);

-- 4. Rejected Settlement - Medical Claim (for demo, assuming it's an internal product)
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    claimant_phone, insured_first_name, insured_last_name, settlement_date,
    settlement_amount, currency_code, settlement_status, negotiator_agent_name, notes
) VALUES (
    104, 'CL2025-004-MED', 'POL-MED456', 'Medical', DATE '2025-02-20',
    'Hospitalization for unexpected illness', 'Giulia', 'Rossi', 'giulia.rossi@example.com',
    '+393331234567', 'Giulia', 'Rossi', DATE '2025-03-25',
    0.00, 'EUR', 'Rejected', 'Marco Bianchi', 'Claim denied due to pre-existing condition.'
);

-- 5. Proposed Settlement - Property Damage (High Value)
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    insured_first_name, insured_last_name, settlement_date, settlement_amount,
    currency_code, settlement_status, negotiator_agent_name, notes
) VALUES (
    105, 'CL2025-005-PROP', 'POL-PRT789', 'Property', DATE '2025-02-10',
    'Fire damage to commercial building', 'Helena', 'Kowalski', 'helena.kowalski@example.com',
    'Jan', 'Kowalski', DATE '2025-04-10',
    250000.00, 'EUR', 'Proposed', 'Anna Nowak', 'Large claim, awaiting formal acceptance.'
);

-- 6. Accepted Settlement - Auto Theft, No Release Yet
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    claimant_phone, insured_first_name, insured_last_name, settlement_date,
    settlement_amount, currency_code, settlement_status, payment_due_date,
    negotiator_agent_name, notes
) VALUES (
    106, 'CL2025-006-THEFT', 'POL-VEH321', 'Auto', DATE '2025-03-05',
    'Vehicle stolen from parking lot', 'Ingrid', 'Müller', 'ingrid.muller@example.com',
    '+491517654321', 'Ingrid', 'Müller', DATE '2025-04-01',
    18000.00, 'EUR', 'Accepted', DATE '2025-04-25',
    'Stefan Weber', 'Sent release document for signature.'
);

-- 7. Paid Settlement - Personal Liability (Minor)
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    insured_first_name, insured_last_name, settlement_date, settlement_amount,
    currency_code, settlement_status, release_signed_date, payment_due_date,
    payment_paid_date, negotiator_agent_name, notes
) VALUES (
    107, 'CL2025-007-LIAB', 'POL-PLB654', 'Personal Liability', DATE '2025-02-05',
    'Minor slip and fall on insured property', 'Kurt', 'Watson', 'kurt.watson@example.com',
    'Paul', 'Schneider', DATE '2025-03-10',
    800.00, 'EUR', 'Paid', DATE '2025-03-12',
    DATE '2025-03-18', DATE '2025-03-17', 'Sabine Fischer', 'Claim closed.'
);

-- 8. Proposed Settlement - Marine (Demo Specific)
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    insured_first_name, insured_last_name, settlement_date, settlement_amount, currency_code,
    settlement_status, negotiator_agent_name, notes
) VALUES (
    108, 'CL2025-008-MRNE', 'POL-MRN111', 'Marine', DATE '2025-03-10',
    'Damage to cargo during transit', 'Liam', 'O''Connell', 'liam.oconnell@example.com',
    'Brenda', 'Kelly', DATE '2025-04-15',
    12000.00, 'EUR', 'Proposed', 'Fiona Murphy', 'Negotiating repair costs with claimant.'
);

-- 9. Accepted Settlement - Auto Accident (Larger), Payment Pending
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    insured_first_name, insured_last_name, settlement_date, settlement_amount,
    currency_code, settlement_status, release_signed_date, payment_due_date,
    negotiator_agent_name, notes
) VALUES (
    109, 'CL2025-009-ACC', 'POL-AT555', 'Auto', DATE '2025-01-20',
    'Multi-vehicle collision, personal injury', 'Nadine', 'Dubois', 'nadine.dubois@example.com',
    'Olivier', 'Leroi', DATE '2025-03-01',
    45000.00, 'EUR', 'Accepted', DATE '2025-03-10',
    DATE '2025-03-30', 'Sophie Martin', 'Complex claim, now awaiting final payment.'
);

-- 10. Proposed Settlement - Disability Claim (Long Term)
INSERT INTO pame_settlement_demo (
    settlement_id, claim_number, policy_number, policy_type, incident_date,
    incident_description, claimant_first_name, claimant_last_name, claimant_email,
    insured_first_name, insured_last_name, settlement_date, settlement_amount,
    currency_code, settlement_status, negotiator_agent_name, notes
) VALUES (
    110, 'CL2025-010-DIS', 'POL-DSB222', 'Disability', DATE '2025-02-01',
    'Long-term disability due to accident', 'Patrick', 'Wagner', 'patrick.wagner@example.com',
    'Patrick', 'Wagner', DATE '2025-04-01',
    60000.00, 'EUR', 'Proposed', 'Michael Keller', 'Settlement offer sent for review of long-term care.'
);

COMMIT;

create table pame_files (
  file_name    varchar2(255 char) PRIMARY KEY,
  file_content blob not null,
  mime_type    varchar2(255 char) not null
);

create table pame_users
(
  user_id    varchar2(255 char) not null
    primary key,
  first_name varchar2(100 char) not null,
  last_name  varchar2(100 char) not null,
  email      varchar2(255 char) not null
    unique,
  phone      varchar2(20 char),
  created_at timestamp(6)       not null,
  updated_at timestamp(6)       not null
);

INSERT INTO PAME_USERS (USER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CREATED_AT, UPDATED_AT) VALUES ('user1', 'Alice', 'Smith', 'alice.smith@example.com', '123-456-7890', TIMESTAMP '2025-09-05 15:47:33.256545', TIMESTAMP '2025-09-05 15:47:33.256545');
INSERT INTO PAME_USERS (USER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CREATED_AT, UPDATED_AT) VALUES ('user2', 'Bob', 'Johnson', 'apex_fan@example.com', '234-567-8901', TIMESTAMP '2025-09-05 15:47:33.256545', TIMESTAMP '2025-09-05 15:47:33.256545');
INSERT INTO PAME_USERS (USER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CREATED_AT, UPDATED_AT) VALUES ('user3', 'Charlie', 'Williams', 'charlie.williams@example.com', '345-678-9012', TIMESTAMP '2025-09-05 15:47:33.256545', TIMESTAMP '2025-09-05 15:47:33.256545');

commit;
