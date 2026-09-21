# Flask-AppBuilder's ab_user table: id, first_name, last_name, username,
# password, active, email, ...
class SupersetUser < SupersetRecord
  self.table_name = "ab_user"
end
