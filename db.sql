CREATE TABLE students (
  id serial PRIMARY KEY,
  name text NOT NULL UNIQUE,
  password text NOT NULL UNIQUE
);


CREATE TABLE checkboxes (
  id serial PRIMARY KEY,
  day text NOT NULL,
  checked boolean DEFAULT false,
  student_id integer NOT NULL REFERENCES students (id) ON DELETE CASCADE
);
