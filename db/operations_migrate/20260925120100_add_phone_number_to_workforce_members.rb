class AddPhoneNumberToWorkforceMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :workforce_members, :phone_number, :string
  end
end
