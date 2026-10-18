class AddAppContextToLaunchContexts < ActiveRecord::Migration[7.0]
  # CDS Hooks のカードのリンク(type: smart)が持つ appContext。EHR が起動文脈と一緒に預かり、
  # トークン応答の appContext でアプリに渡す。
  def change
    add_column :launch_contexts, :app_context, :text
  end
end
