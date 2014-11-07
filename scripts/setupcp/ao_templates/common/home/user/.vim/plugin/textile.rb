#!/usr/bin/env ruby

require 'rubygems'
require 'redcloth'

File.open(ARGV[0], "r") do |txt_file|
  if not ARGV[1]
    of = $stdout
  else
    of = File.new(ARGV[1], "w")
  end
  of.puts '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"'
  of.puts '   "http://www.w3.org/TR/html4/strict.dtd">'
  of.puts '<html>'
  of.puts '<head>'
  of.puts '<title></title>'
  of.puts '<LINK href="notes.css" rel="stylesheet" type="text/css">'
  of.puts '</head>'
  of.puts '<body class="notes">'
  of.puts RedCloth.new(txt_file.readlines(nil)[0]).to_html
  of.puts '</body>'
  of.puts '</html>'
  if ARGV[1]
    of.close
  end
end
