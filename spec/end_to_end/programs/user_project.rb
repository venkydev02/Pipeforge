# frozen_string_literal: true

# A user's migration: moving the employees of an old HR system into the table of their new application.
require "json"
require "pipeforge"

ActiveRecord::Base.establish_connection(adapter: "postgresql", database: "pipeforge_test")
ActiveRecord::Schema.verbose = false

def drop_tables
  ActiveRecord::Base.connection.drop_table(:e2e_employees, if_exists: true)
  ActiveRecord::Base.connection.drop_table(:e2e_departments, if_exists: true)
end

drop_tables
at_exit { drop_tables }

ActiveRecord::Schema.define do
  create_table(:e2e_departments) { |table| table.string :name }
  create_table(:e2e_employees) do |table|
    table.string :email
    table.string :full_name
    table.integer :status
    table.decimal :salary, precision: 8, scale: 2
    table.date :joined_on
    table.references :department, foreign_key: {to_table: :e2e_departments}
    table.string :phone # new in this application: the old system never kept it
  end
end

class E2eDepartment < ActiveRecord::Base
  self.table_name = "e2e_departments"
end

class E2eEmployee < ActiveRecord::Base
  self.table_name = "e2e_employees"
  enum :status, {active: 0, on_leave: 1, inactive: 2}
  belongs_to :department, class_name: "E2eDepartment", optional: true
  validates :email, presence: true, uniqueness: true
end

engineering = E2eDepartment.create!(name: "Engineering")

# The export of the old system, with the mistakes such a file has:
#   row 1  correct
#   row 2  a salary typed with two zeros too many, more than the column holds
#   row 3  correct; on leave, and the salary was never filled in ("N/A")
#   row 4  a joining date that is not in the calendar
#   row 5  a department that no longer exists
#   row 6  correct; this person has left
#   row 7  the same person as row 1, exported twice
#   row 8  no email, which the application requires
#   row 9  a status the application does not have
# "Remarks" is a note of the old system that the application has no use for.
File.write("employees.csv", <<~CSV)
  Email,Full Name,Status,Salary,Date of Joining,Department Id,Remarks
  priya@example.com,Priya Raman,Working,85000.00,2021-04-12,#{engineering.id},team lead
  ravi@example.com,Ravi Kumar,Working,8500000.00,2020-11-02,#{engineering.id},
  arjun@example.com,Arjun Mehta,On Leave,N/A,2022-01-03,#{engineering.id},sabbatical
  sana@example.com,Sana Sheikh,Working,64000.00,2023-02-30,#{engineering.id},
  john@example.com,John Mathew,Working,59000.00,2018-06-18,999999,
  meena@example.com,Meena Iyer,Left,72000.00,2019-07-22,#{engineering.id},
  priya@example.com,Priya Raman,Working,85000.00,2021-04-12,#{engineering.id},
  ,Divya Nair,Working,61000.00,2022-09-05,#{engineering.id},
  kiran@example.com,Kiran Das,Contractor,45000.00,2023-05-15,#{engineering.id},
CSV

# The old system's words for a status, and the application's.
STATUS_MAPPING = {"Working" => "active", "On Leave" => "on_leave", "Left" => "inactive"}.freeze

# The old system writes "N/A" where nothing was filled in.
SALARY_MAPPING = {"N/A" => nil}.freeze

def new_engine
  Pipeforge::Engine.new(source_io: File.open("employees.csv"), target_model_name: "E2eEmployee")
end

def mapped_columns
  {
    email: {source_column_name: "Email"},
    full_name: {source_column_name: "Full Name"},
    status: {source_column_name: "Status", value_mapping: STATUS_MAPPING},
    salary: {source_column_name: "Salary", value_mapping: SALARY_MAPPING},
    joined_on: {source_column_name: "Date of Joining"},
    department_id: {source_column_name: "Department Id"}
  }
end

# What is in the table, as the user would check it.
def stored_employees
  E2eEmployee.includes(:department).order(:id).map do |employee|
    [employee.email, employee.status, employee.salary&.to_s("F"), employee.joined_on&.iso8601, employee.department&.name]
  end
end
