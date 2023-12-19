#!/usr/bin/env ruby
# encoding: UTF-8
require 'optparse'
require 'parallel'
require 'etc'
require 'benchmark'
require 'colorize'

options = { after_context: 0, before_context: 0 }
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
        options[:ignore_case] = true
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
    context_before = []
    context_after = []
   
   

    

    if options[:ignore_case] && pattern.include?('\w') && pattern.include?('\s')
        pattern = pattern.encode('UTF-8').downcase 
        pattern_without_w = pattern.gsub('\w', '[\p{L}\p{N}_à]')
        
        pattern_regex = Regexp.new(pattern_without_w)  
       
    else
        pattern = pattern.encode('UTF-8')
        pattern_without_w = pattern.gsub('\w', '[\p{L}\p{N}_à]')
        pattern_regex = options[:ignore_case] ? Regexp.new(pattern_without_w.to_s, Regexp::IGNORECASE) : Regexp.new(pattern_without_w)    
        
    
    end

    
    File.open(file, 'r:UTF-8')  do |f| 
        while chunk = f.read(chunk_size)
            lines = chunk.split("\n")
            line_buffer ||= ""
            lines[0] = line_buffer.to_s + lines[0].to_s unless line_buffer.nil? || line_buffer.empty?
            if chunk.end_with?("\n")
                line_buffer = ""
            else
                
                line_buffer = f.eof? ? "" : lines.pop
            end
            lines.each_with_index do |line, index|
            
                line_number += 1
                if options[:ignore_case] && pattern.include?('\w') && pattern.include?('\s')
                    line2 = line.force_encoding('UTF-8').scrub("?").downcase
                elsif pattern.include?('\w') || pattern.include?('\s')
                    line2 = line.force_encoding('UTF-8')
                elsif pattern.include?('\w')
                    line2 = line.scrub("?")
                else
                    line2 = line
                end

                
                context_before.shift if context_before.size > options[:before_context]&& options[:before_context]

                
                if line2.match(pattern_regex)
                    next if binary_file?(file)
                    
                    
                    line = line.gsub(pattern_regex) { |match| match.red } if options[:color]

                    if options[:before_context]
                    context_before.each_with_index do |context_line, i|
                        linen = line_number - context_before.size + i
                        output_line = "#{file}-#{line_number - context_before.size + i}-#{context_line}"
                        unless printed_lines[output_line]||context_line.match(pattern_regex)||printed_lines[linen]
                            puts output_line
                            printed_lines[output_line] = true
                        end
                    end
                    end

                    
                    if options[:no_heading]
                        puts "#{file}:#{line_number}:#{line}"
                       
                    else
                        puts "#{file}"
                        puts "#{line_number}:#{line}"
                        
                    end

                    
                    if options[:after_context]
                    (1..options[:after_context]).each do |i|
                        context_line = lines[index + i] if index + i < lines.size
                        linen = line_number + i
                    
                        begin
                            output_line = "#{file}-#{line_number + i}-#{context_line}"
                            
                            unless printed_lines[linen] || context_line.match(pattern_regex)||context_line.nil?
                                puts output_line
                                printed_lines[linen] = true
                            end
                        rescue NoMethodError
                           
                            total_lines = `wc -l "#{file}"`.strip.split(' ')[0].to_i
                            total_lines += 1 unless `tail -c 1 "#{file}"` == "\n"
                            line4 = "#{file}-#{line_number + i}-#{File.readlines(file)[line_number + i - 1]}"
                            if line_number + i <= total_lines && !printed_lines[output_line] && !line4.match(pattern_regex)&& !printed_lines[line4] 
                            puts line4
                            
                            printed_lines[linen] = true
                            printed_lines[output_line] = true
                            
                            end
                            if line_number + i == total_lines && !printed_lines[line4] && !line4.match(pattern_regex)&& !printed_lines[linen] 
                                puts output_line
                                
                                printed_lines[linen] = true
                                printed_lines[line4] = true
                            end
                        end
                    end
                    end
                end
                    

                context_before << line if options[:before_context]
                
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
  
