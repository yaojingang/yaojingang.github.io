#!/usr/bin/env ruby
# frozen_string_literal: true

require "io/console"
require "fileutils"
require "json"
require "securerandom"

abort "请在电脑上的终端运行此设置程序。" unless $stdin.tty?
directory = File.expand_path("~/.config/laoyao-geo")
destination = File.join(directory, "credentials.json")
puts "GEO 内测版 · 密钥设置"
puts "输入过程不会显示字符，密钥保存在你的电脑上。"
print "粘贴 DeepSeek API Key，然后按回车："
key = $stdin.noecho(&:gets).to_s.strip
puts
abort "Key 格式不完整，请重新运行。" unless key.start_with?("sk-") && key.length.between?(16, 512) && !key.match?(/\s/)
print "设置内测访问口令（至少 12 个字符），然后按回车："
password = $stdin.noecho(&:gets).to_s.chomp
puts
abort "访问口令至少需要 12 个字符。" unless password.length.between?(12, 256)
print "再次输入内测访问口令："
confirmation = $stdin.noecho(&:gets).to_s.chomp
puts
abort "两次口令不同，请重新运行。" unless password == confirmation
FileUtils.mkdir_p(directory, mode: 0700)
File.chmod(0700, directory)
temporary = File.join(directory, ".credentials-#{SecureRandom.hex(8)}")
File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
  file.write(JSON.generate("deepseek_api_key" => key, "access_password" => password))
end
File.rename(temporary, destination)
puts "设置完成。文件权限已限制为仅当前用户可读写。"
puts "配置位置：#{destination}"
puts "本次内测预算上限：50 元。"
puts "请在聊天中回复“Key 已配置”，请保留完整密钥和口令在本机。"
