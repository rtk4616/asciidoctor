# Public: Methods for retrieving lines from Asciidoc documents
class Asciidoctor::Reader

  include Asciidoctor

  # Public: Get the String document source.
  attr_reader :source

  # Public: Get the String Array of lines parsed from the source
  attr_reader :lines

  # Public: Initialize the Reader object.
  #
  # data       - The Array of Strings holding the Asciidoc source document. The
  #              original instance of this Array is not modified
  # document   - The document with which this reader is associated. Used to access
  #              document attributes
  # overrides  - A Hash of attributes that were passed to the Document and should
  #              prevent attribute assignments or removals of matching keys found in
  #              the document
  # block      - A block that can be used to retrieve external Asciidoc
  #              data to include in this document.
  #
  # Examples
  #
  #   data   = File.readlines(filename)
  #   reader = Asciidoctor::Reader.new data
  def initialize(data = [], document = nil, overrides = nil, &block)
    # if document is nil, we assume this is a preprocessed string
    if document.nil?
      @lines = data.is_a?(String) ? data.lines.entries : data.dup
    elsif !data.empty?
      @overrides = overrides || {}
      @document = document
      process(data.is_a?(String) ? data.lines.entries : data, &block)
    else
      @lines = []
    end

    # just in case we got some nils floating at the end of our lines after reading a funky document
    @lines.pop until @lines.empty? || !@lines.last.nil?

    @source = @lines.join
    Asciidoctor.debug "Leaving Reader#init, and I have #{@lines.count} lines"
    Asciidoctor.debug "Also, has_lines? is #{self.has_lines?}"
  end

  # Public: Check whether there are any lines left to read.
  #
  # Returns true if !@lines.empty? is true, or false otherwise.
  def has_lines?
    !@lines.empty?
  end

  # Public: Check whether this reader is empty (contains no lines)
  #
  # Returns true if @lines.empty? is true, otherwise false.
  def empty?
    @lines.empty?
  end

  # Private: Strip off leading blank lines in the Array of lines.
  #
  # Returns nil.
  #
  # Examples
  #
  #   @lines
  #   => ["\n", "\t\n", "Foo\n", "Bar\n", "\n"]
  #
  #   skip_blank
  #   => nil
  #
  #   @lines
  #   => ["Foo\n", "Bar\n"]
  def skip_blank
    while has_lines? && @lines.first.strip.empty?
      @lines.shift
    end

    nil
  end

  # Public: Consume consecutive lines containing line- or block-level comments.
  #
  # Returns the Array of lines that were consumed
  #
  # Examples
  #   @lines
  #   => ["// foo\n", "////\n", "foo bar\n", "////\n", "actual text\n"]
  #
  #   comment_lines = consume_comments
  #   => ["// foo\n", "////\n", "foo bar\n", "////\n"]
  #
  #   @lines
  #   => ["actual text\n"]
  def consume_comments
    comment_lines = []
    while !@lines.empty?
      next_line = peek_line
      if next_line.match(REGEXP[:comment_blk])
        comment_lines << get_line
        comment_lines.push(*(grab_lines_until(:preserve_last_line => true) {|line| line.match(REGEXP[:comment_blk])}))
        comment_lines << get_line
      elsif next_line.match(REGEXP[:comment])
        comment_lines << get_line
      else
        break
      end
    end

    comment_lines
  end

  # Skip the next line if it's a list continuation character
  # 
  # Returns nil
  def skip_list_continuation
    if has_lines? && @lines.first.chomp == '+'
      @lines.shift
    end

    nil
  end

  # Public: Get the next line of source data. Consumes the line returned.
  #
  # Returns the String of the next line of the source data if data is present.
  # Returns nil if there is no more data.
  def get_line
    @lines.shift
  end

  # Public: Get the next line of source data. Does not consume the line returned.
  #
  # Returns a String dup of the next line of the source data if data is present.
  # Returns nil if there is no more data.
  def peek_line
    @lines.first.dup if @lines.first
  end

  # Public: Push Array of string `lines` onto queue of source data lines, unless `lines` has no non-nil values.
  #
  # Returns nil
  def unshift(*new_lines)
    @lines.unshift(*new_lines) if !new_lines.empty?
    nil
  end

  # Public: Chomp the String on the last line if this reader contains at least one line
  #
  # Delegates to chomp!
  #
  # Returns nil
  def chomp_last!
    @lines.last.chomp! unless @lines.empty?
    nil
  end

  # Public: Return all the lines from `@lines` until we (1) run out them,
  #   (2) find a blank line with :break_on_blank_lines => true, or (3) find
  #   a line for which the given block evals to true.
  #
  # options - an optional Hash of processing options:
  #           * :break_on_blank_lines may be used to specify to break on
  #               blank lines
  #           * :preserve_last_line may be used to specify that the String
  #               causing the method to stop processing lines should be
  #               pushed back onto the `lines` Array.
  #           * :grab_last_line may be used to specify that the String
  #               causing the method to stop processing lines should be
  #               included in the lines being returned
  #
  # Returns the Array of lines forming the next segment.
  #
  # Examples
  #
  #   reader = Reader.new ["First paragraph\n", "Second paragraph\n",
  #                        "Open block\n", "\n", "Can have blank lines\n",
  #                        "--\n", "\n", "In a different segment\n"]
  #
  #   reader.grab_lines_until
  #   => ["First paragraph\n", "Second paragraph\n", "Open block\n"]
  def grab_lines_until(options = {}, &block)
    buffer = []

    finis = false
    while (this_line = self.get_line)
      Asciidoctor.debug "Processing line: '#{this_line}'"
      finis = true if options[:break_on_blank_lines] && this_line.strip.empty?
      finis = true if !finis && block && yield(this_line)
      if finis
        self.unshift(this_line) if options[:preserve_last_line]
        buffer << this_line if options[:grab_last_line]
        break
      end

      buffer << this_line
    end
    buffer
  end

  # Public: Convert a string to a legal attribute name.
  #
  # name  - The String holding the Asciidoc attribute name.
  #
  # Returns a String with the legal name.
  #
  # Examples
  #
  #   sanitize_attribute_name('Foo Bar')
  #   => 'foobar'
  #
  #   sanitize_attribute_name('foo')
  #   => 'foo'
  #
  #   sanitize_attribute_name('Foo 3 #-Billy')
  #   => 'foo3-billy'
  def sanitize_attribute_name(name)
    name.gsub(/[^\w\-]/, '').downcase
  end

  # Private: Process raw input, used for the outermost reader.
  def process(data, &block)

    raw_source = []

    data.each do |line|
      if inc = line.match(REGEXP[:include_macro])
        if block_given?
          raw_source.concat yield(inc[1])
        else
          raw_source.concat File.readlines(inc[1])
        end
      else
        raw_source << line
      end
    end

    skip_to = nil
    continuing_value = nil
    continuing_key = nil
    @lines = []
    raw_source.each do |line|
      if skip_to
        skip_to = nil if line.match(skip_to)
      elsif continuing_value
        close_continue = false
        # Lines that start with whitespace and end with a '+' are
        # a continuation, so gobble them up into `value`
        if line.match(REGEXP[:attr_continue])
          continuing_value += ' ' + $1
        # An empty line ends a continuation
        elsif line.strip.empty?
          raw_source.unshift(line)
          close_continue = true
        else
          # If this continued line isn't empty and doesn't end with a +, then
          # this is the end of the continuation, no matter what the next line
          # does.
          continuing_value += ' ' + line.strip
          close_continue = true
        end
        if close_continue
          unless attribute_overridden? continuing_key
            @document.attributes[continuing_key] = apply_attribute_value_subs(continuing_value)
          end
          continuing_key = nil
          continuing_value = nil
        end
      elsif line.match(REGEXP[:ifdef_macro])
        attr = $2
        skip = case $1
               when 'ifdef';  !@document.attributes.has_key?(attr)
               when 'ifndef'; @document.attributes.has_key?(attr)
               end
        skip_to = /^endif::#{attr}\[\]\s*\n/ if skip
      elsif line.match(REGEXP[:attr_assign])
        key = sanitize_attribute_name($1)
        value = $2
        if value.match(REGEXP[:attr_continue])
          # attribute value continuation line; grab lines until we run out
          # of continuation lines
          continuing_key = key
          continuing_value = $1  # strip off the spaces and +
          Asciidoctor.debug "continuing key: #{continuing_key} with partial value: '#{continuing_value}'"
        else
          unless attribute_overridden? key
            @document.attributes[key] = apply_attribute_value_subs(value)
            Asciidoctor.debug "Defines[#{key}] is '#{@document.attributes[key]}'"
            if key == 'backend'
              @document.update_backend_attributes()
            end
          end
        end
      elsif line.match(REGEXP[:attr_delete])
        key = sanitize_attribute_name($1)
        unless attribute_overridden? key
          @document.attributes.delete(key)
        end
      elsif !line.match(REGEXP[:endif_macro])
        while line.match(REGEXP[:attr_conditional])
          value = @document.attributes.has_key?($1) ? $2 : ''
          line.sub!(conditional_regexp, value)
        end
        # leave line comments in as they play a role in flow (such as a list divider)
        @lines << line
      end
    end

    # Process bibliography references, so they're available when text
    # before the reference is being rendered.
    # FIXME we don't have support for bibliography lists yet, so disable for now
    # plus, this should be done while we are walking lines above
    #@lines.each do |line|
    #  if biblio = line.match(REGEXP[:biblio])
    #    @document.references[biblio[1]] = "[#{biblio[1]}]"
    #  end
    #end

    #Asciidoctor.debug "About to leave Reader#process, and references is #{@document.references.inspect}"
  end

  # Internal: Determine if the attribute has been overridden in the document options
  #
  # key - The attribute key to check
  #
  # Returns true if the attribute has been overridden, false otherwise
  def attribute_overridden?(key)
    @overrides.has_key?(key) || @overrides.has_key?(key + '!')
  end

  # Internal: Apply substitutions to the attribute value
  #
  # If the value is an inline passthrough macro (e.g., pass:[text]), then
  # apply the substitutions defined on the macro to the text. Otherwise,
  # apply the verbatim substitutions to the value.
  #
  # value - The String attribute value on which to perform substitutions
  #
  # Returns The String value with substitutions performed.
  def apply_attribute_value_subs(value)
    if value.match(REGEXP[:pass_macro_basic])
      # copy match for Ruby 1.8.7 compat
      m = $~
      subs = []
      if !m[1].empty?
        sub_options = Asciidoctor::Substituters::COMPOSITE_SUBS.keys + Asciidoctor::Substituters::COMPOSITE_SUBS[:normal]
        subs = m[1].split(',').map {|sub| sub.to_sym} & sub_options
      end
      if !subs.empty?
        @document.apply_subs(m[2], subs)
      else
        m[2]
      end
    else
      @document.apply_header_subs(value)
    end
  end
end