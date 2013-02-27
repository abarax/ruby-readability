#require 'rubygems'
require 'nokogiri'
require 'open-uri'

class Readability
  
  class Nokogiri::XML::Node
    attr_accessor :readability
  end


  def initialize(html_page)
    @regexps = {:unlikelyCandidates => /combx|comment|disqus|extra|foot|header|menu|remark|rss|shoutbox|sidebar|sponsor|ad-break|agegate|pagination|pager|popup/i,
                :okMaybeItsACandidate =>  /and|article|body|column|main|shadow/i,
                :divToPElements => /<(a|blockquote|dl|div|img|ol|p|pre|table|ul)/i,
                :extraneous => /print|archive|comment|discuss|e[\-]?mail|share|reply|all|login|sign|single/i,
                :trim => /^\s+|\s+$/,
                :normalize => /\s{2,}/,
                :positive => /article|body|content|entry|hentry|main|page|pagination|post|text|blog|story/i,
                :negative => /combx|comment|com-|contact|foot|footer|footnote|Dmasthead|media|meta|outbrain|promo|related|scroll|shoutbox|sidebar|sponsor|shopping|tags|tool|widget/i,
                :nextLink => /(next|weiter|continue|>([^\|]|$)|([^\|]|$))/i,
                :prevLink =>/(prev|earl|old|new|<)/i
      }
    @url = html_page
    @html_doc = Nokogiri::HTML(open(html_page))
    @document = Nokogiri::XML::Document.new
  end

  def get_article_title  
    @html_doc.xpath('//title').text
    #potentially add more smarts here to handle junk titles. i.e. where titles are longer than 150 chars or less than 10
    # in that case jsut use the first H1 that you find.
  end
  
  def grab_article
    
    @body = @html_doc.xpath('//body').first
    count= 0
    nodes_to_score = []
    
    @body.traverse do |node|
      #Remove unlikely candidates  
      if node['id'] =~ @regexps[:unlikelyCandidates] || node['class']  =~ @regexps[:unlikelyCandidates]
         node.remove
         count = count + 1
      end
      
       %w(IMG A OBJECT SCRIPT IFRAME).each {|t| node.remove if node.name.upcase == t } 
      
      
      %w(P TD PRE).each {|t| nodes_to_score << node if node.name.upcase == t } 

      if node.name.upcase == 'DIV'
        if node.inner_html.index(@regexps[:divToPElements]) == nil
          new_node = Nokogiri::XML::Node.new("p", node.document)
          new_node.content = node.inner_html
          #puts new_node.inner_html
          #node.replace(new_node) 
          nodes_to_score << new_node   
        elsif node.inner_html.empty?
          node.remove
        end   
      end
    end
  
    candidates = []
    nodes_to_score.each do |node|
      parent_node = node.parent
      grandparent_node = parent_node ? parent_node.parent : nil
      inner_text = node.content
      
      next if parent_node.nil? 
      next if inner_text.length < 25
      
      # Initialize readability data for the parent. 
      if !parent_node.readability
        initialize_node(parent_node)
        candidates.push(parent_node)
      end
     
      if !grandparent_node.nil? && !grandparent_node.readability
        initialize_node(grandparent_node)
        candidates.push(grandparent_node)
      end
      
      content_score = 0
      content_score++
      content_score += inner_text.split(',').length
      content_score += (inner_text.length / 100) < 3 ? (inner_text.length / 100) : 3
      
      if parent_node
        parent_node.readability[:content_score] += content_score
      end
      
      if grandparent_node
        grandparent_node.readability[:content_score] += content_score/2
      end
    end
    
    top_candidate = nil
    candidates.each do |candidate|
      candidate.readability[:content_score] = candidate.readability[:content_score] * (1 - get_link_density(candidate))
      
      p "Candidate: " << candidate.name 
      if candidate['class']
        p " (" << candidate['class']
      end
      if candidate['id'] 
        p ":" << candidate['id']
      end
      p ") with score " 
      p candidate.readability[:content_score]
      
      if !top_candidate || candidate.readability[:content_score] > top_candidate.readability[:content_score] 
        top_candidate = candidate
      end
    end
    
    article_content = Nokogiri::XML::Node.new("div", @document)
    
    #xxx
    if top_candidate.blank?
      "nil"
    else
      if top_candidate.parent.blank?
        'nil'
      else
        sibling_score_threshold = 10 > top_candidate.readability[:content_score] * 0.2 ? 10 : top_candidate.readability[:content_score] * 0.2
        sibling_node = top_candidate.parent.children
    
        sibling_node.each do |sibling|
      
          append = false
      
          next if !sibling
      
          append = true if sibling == top_candidate
      
          content_bonus = 0
          # Give a bonus if sibling nodes and top candidates have the example same classname */
          if sibling['class'] == top_candidate['class'] && top_candidate['class'] != ""
            content_bonus += top_candidate.readability[:content_score] * 0.2
          end
      
          if sibling.readability && (sibling.readability[:content_score] + content_bonus) >= sibling_score_threshold
              append = true
          end
      
          if sibling.name == "P"
            link_density = get_link_density(sibling)
            node_content = sibling.text
            node_length  = node_content.length

            if node_length > 80 && link_density < 0.25
              append = true
            elsif node_length < 80 && link_density == 0 && node_content =~ /\.( |$)/ 
              append = true
            end
          end
                      
          if append
          #  p article_content.inner_html
            article_content.add_child(sibling)
          end
      
        end
        article_content
      end
    end
  end

  def get_link_density(node)
        links = node.css('a')
        text_length = node.content.length
        link_length = 0
        links.each do | link |
            link_length += link.text.length
        end      

        link_length / text_length
  end


  def initialize_node (node) 
        node.readability = {:content_score => 0}         

        case node.name 
            when 'DIV'
                node.readability[:content_score] += 5
            when 'PRE'
            when 'TD'
            when 'BLOCKQUOTE'
                node.readability[:content_score] += 3
            when 'ADDRESS'
            when 'OL'
            when 'UL'
            when 'DL'
            when 'DD'
            when 'DT'
            when 'LI'
            when 'FORM'
                node.readability[:content_score] -= 3
            when 'H1'
            when 'H2'
            when 'H3'
            when 'H4'
            when 'H5'
            when 'H6'
            when 'TH'
                node.readability[:content_score] -= 5
        end
       
        node.readability[:content_score] += get_class_weight(node)
  end

  def get_class_weight (node) 
    weight = 0

    # Look for a special classname 
    if node['class'] =~ @regexps[:negative] 
      weight -= 25 
    end

    if node['class'] =~ @regexps[:positive]
      weight += 25 
    end

    # Look for a special ID 
    if node['id'] =~ @regexps[:negative] 
      weight -= 25 
    end

    if node['id'] =~ @regexps[:positive]
      weight += 25 
    end

    weight
  end
  
  def grab_article_text_only
    grabArticle.to_str.strip.gsub(/<div.*>|<p.*>|<table.*>|<tr.*>|\n|\t|\r/, '').squeeze(" ").gsub(/[^a-zA-z\s]/,'')
  end

  def get_next_page_link
    all_links = @html_doc.css('a')
    base_url = @url.scan(/^(http:\/\/[\w\d\-\.]+)(\/.*)$/).first.first
    
    p base_url
    
    possible = {}
    all_links.each do |link|
      
      href = link['href']
      
      next if link.text =~ @regexps[:extraneous] || link.text.length > 25 || href.match(base_url) == nil || href.sub(base_url, '').match(/\d/) == nil

      link_href_left_over = href.sub(base_url, '')
      
      if !possible.key? href 
        possible[href] = { :score => 0, :linkText => link.text, :href => href }
      else
        possible[href][:linkText] << link.text
      end
      
      our_link = possible[href]
      link_data = link.text
      link_data << link['id'] if link['id']
      link_data << link['class'] if link['class']
      
      our_link[:score] -= 25 if !href.include? base_url 
            
      our_link[:score] += 50 if link_data =~ @regexps[:nextLink]
      
      our_link[:score] += 25 if link_data =~ /pag(e|ing|inat)/i
      
      our_link[:score] -= 65 if link_data =~ /(first|last)/i && !link.text =~ @regexps[:nextLink]
      
      our_link[:score] -= 50 if link_data =~ @regexps[:extraneous] || link_data =~ @regexps[:negative]
      
      our_link[:score] -= 200 if link_data =~ @regexps[:prevLink]
      
      parent = link.parent
      positive_match = false
      negative_match = false
      
      while !parent.is_a? Nokogiri::HTML::Document do
        
        parent_class_and_id = '' 
        parent_class_and_id  << parent['class'] if !parent['class'].nil?
        parent_class_and_id << parent['id'] if !parent['id'].nil?
        
        if !positive_match && parent_class_and_id && parent_class_and_id =~ /pag(e|ing|inat)/i
          positive_match = true
          our_link[:score] += 25
        end
        if !negative_match && parent_class_and_id && parent_class_and_id =~ @regexps[:negative]
          if !parent_class_and_id =~ @regexps[:positive]
            our_link[:score] -= 25
            negative_match = true 
          end
        end
        
        parent = parent.parent
        
      end
      
      our_link[:score] += 25 if href =~ /p(a|g|ag)?(e|ing|ination)?(=|\/)[0-9]{1,2}/i || href =~ /(page|paging)/i
      
      our_link[:score] -= 15 if href =~ @regexps[:extraneous]
      
      if link.text.to_i
        if link.text.to_i == 1
          our_link[:score] -= 15 
        else
          our_link[:score] += [0, 10 - link.text.to_i].max
        end
      end
      
      p possible[href][:href]
      p possible[href][:score]
      
      p possible.values
      
    end
  end
  
  def grab_entire_article
    grab_article_text_only
    
    #while get_next_page_link
    
  end

end

r = Readability.new('http://www.abc.net.au/news/2013-02-28/police-seize-australia27s-biggest-ever-ice-haul/4544306')
p r.grab_entire_article
