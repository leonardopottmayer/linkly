-- 20261020234558-create-table-idt001-user.up.sql
CREATE TABLE identity.idt001_user (
	id UUID NOT NULL DEFAULT uuidv7(),
	username VARCHAR(30) NOT NULL,
	email VARCHAR(255) NOT NULL,
	password_hash TEXT NOT NULL,
	name VARCHAR(150) NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT current_timestamp,
	updated_at TIMESTAMPTZ NULL
);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT pk_idt001 PRIMARY KEY (id);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT uq_idt001_username UNIQUE (username);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT uq_idt001_email UNIQUE (email);

ALTER TABLE identity.idt001_user
ADD CONSTRAINT ck_idt001_username CHECK (username ~ '^[a-z0-9_-]{3,30}$');
