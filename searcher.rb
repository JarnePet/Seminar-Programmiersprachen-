#!/usr/bin/env ruby
# encoding: UTF-8
require 'optparse'
require 'parallel'
require 'etc'
require 'benchmark'
require 'colorize'

options = {}
OptionParser.new do |opts|
    opts.banner = "Usage: searcher [OPTIONS] PATTERN [PATH ...]"
    opts.on("-A", "--after-context LINES", Integer, "Prints the given number of following lines for each match") do |a|
        options[:after_context] = a
    end
    opts.on("-B", "--before-context LINES", Integer, "Prints the given number of preceding lines for each match") do |b|
        options[:before_context] = b
    end
    opts.on("-c", "--color", "Print with colors, highlighting the matched phrase in the output") do |c|
        options[:color] = true
    end
    opts.on("-C", "--context LINES", Integer, "Prints the number of preceding and following lines for each match. This is equivalent to setting --before-context and --after-context") do |c|
        options[:before_context] = c
        options[:after_context] = c
    end
    opts.on("-h", "--hidden", "Search hidden files and folders") do |h|
        options[:hidden] = h
    end
    opts.on("-i", "--ignore-case", "Search case insensitive") do |i|
        options[:ignore_case] = i
    end
    opts.on("--no-heading", "Prints a single line including the filename for each match, instead of grouping matches by file") do |nh|
        options[:no_heading] = true
    end
    opts.on("--help", "Print this message") do
        puts opts
        exit
    end
end.parse!(into: options)

path = ARGV.pop || '.'
pattern = ARGV.join(' ')

def binary_file?(file)
    `file -b --mime-encoding #{file}`.strip == 'binary'
end

def search_file(file, pattern, options)
    chunk_size = 400000
    line_number = 0
    line_buffer = []
    printed_lines = {}

    pattern = pattern.encode('UTF-8')
    pattern_without_w = pattern.gsub('\w', '[\p{L}\p{N}_à]')
    pattern_regex = options[:ignore_case] ? Regexp.new(pattern_without_w.to_s, Regexp::IGNORECASE) : Regexp.new(pattern_without_w)

    File.open(file, 'r:UTF-8')  do |f|
        while chunk = f.read(chunk_size)
            lines = chunk.split("\n")
            line_buffer ||= ""
            lines[0] = line_buffer.to_s + lines[0].to_s unless line_buffer.nil? || line_buffer.empty?
            if chunk.end_with?("\n")
                line_buffer = ""
            else
                line_buffer = lines.pop
            end
            lines.each do |line|
                line_number += 1
                line = line.force_encoding('UTF-8') if pattern.include?('\w')|| pattern.include?('\s')
                line = line.scrub("?") if pattern.include?('\w')
                        
                    if line.match(pattern_regex)
                    next if binary_file?(file)
                        line = line.gsub(pattern_regex) { |match| match.red } if options[:color]
                        if options[:before_context]
                            (line_number - options[:before_context]..line_number-1).each do |n|
                                if printed_lines["#{file}-#{n-1}-#{lines[n-2]}"]
                                            puts "--"
                                end
                                line2 = "#{file}-#{n}-#{File.readlines(file)[n - 1]}"
                                line1 = "#{file}-#{n+1}-#{File.readlines(file)[n]}"
                                if line_number <= options[:before_context] 
                                unless n == -1 ||line1.match(pattern_regex)
                                            
                                puts line1
                                printed_lines[line1] = true
                                end
                            end
                                unless printed_lines[line2] || line2.match(pattern_regex)|| line_number <= options[:before_context] 
                                puts line2
                                            
                                printed_lines[line2] = true
                                end
                                        
                                break if n < 1
                                end
                            end
                        if options[:after_context]
                            (line_number + 1..line_number + options[:after_context]).each do |n|
                            line3 = File.readlines(file)[n - 1]
                            break if line3.nil? || line3.match(pattern_regex)
                            line3 = "#{file}-#{n}-#{File.readlines(file)[n - 1]}"
                            unless printed_lines[line3] || line3.match(pattern_regex)
                                puts line3
                                printed_lines[line3] = true
                                end
                            end
                            end
                        if options[:no_heading]
                            puts "#{file}:#{line_number}:#{line}"
                        else
                            puts "#{file}"
                            puts "#{line_number}:#{line}"
                            
                        end
                    end
                    end
                end
             end
            
        end
    


if File.directory?(path)
    files = Dir.glob("#{path}/**/*", File::FNM_DOTMATCH).reject { |file| File.directory?(file) || (!options[:hidden] && File.basename(file).start_with?('.')) }
else
    files = [path]
end

num_processes = Etc.nprocessors
Parallel.each(files, in_processes: num_processes) do |file|
    search_file(file, pattern, options)
end
  
