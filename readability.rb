#require 'rubygems'
require 'nokogiri'
require 'open-uri'

class Readability
  
  class Nokogiri::XML::Node
    attr_accessor :readability
  end


  def initialize(htmlPage)
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
    @url = htmlPage
    @htmlDoc = Nokogiri::HTML(open(htmlPage))
    @document = Nokogiri::XML::Document.new
  end

  def getArticleTitle  
    @htmlDoc.xpath('//title').text
    #potentially add more smarts here to handle junk titles. i.e. where titles are longer than 150 chars or less than 10
    # in that case jsut use the first H1 that you find.
  end
  
  def grabArticle
    
    @body = @htmlDoc.xpath('//body').first
    count= 0
    nodesToScore = []
    
    @body.traverse do |node|
      #Remove unlikely candidates  
      if node['id'] =~ @regexps[:unlikelyCandidates] || node['class']  =~ @regexps[:unlikelyCandidates]
         node.remove
         count = count + 1
      end
      
       %w(IMG A OBJECT SCRIPT IFRAME).each {|t| node.remove if node.name.upcase == t } 
      
      
      %w(P TD PRE).each {|t| nodesToScore << node if node.name.upcase == t } 

      if node.name.upcase == 'DIV'
        if node.inner_html.index(@regexps[:divToPElements]) == nil
          newNode = Nokogiri::XML::Node.new("p", node.document)
          newNode.content = node.inner_html
          #puts newNode.inner_html
          #node.replace(newNode) 
          nodesToScore << newNode   
        elsif node.inner_html.empty?
          node.remove
        end   
      end
    end
  
    candidates = []
    nodesToScore.each do |node|
      parentNode = node.parent
      grandParentNode = parentNode ? parentNode.parent : nil
      innerText = node.content
      
      next if parentNode.nil? 
      next if innerText.length < 25
      
      # Initialize readability data for the parent. 
      if !parentNode.readability
        initializeNode(parentNode)
        candidates.push(parentNode)
      end
     
      if !grandParentNode.nil? && !grandParentNode.readability
        initializeNode(grandParentNode)
        candidates.push(grandParentNode)
      end
      
      contentScore = 0
      contentScore++
      contentScore += innerText.split(',').length
      contentScore += (innerText.length / 100) < 3 ? (innerText.length / 100) : 3
      
      if parentNode
        parentNode.readability[:contentScore] += contentScore
      end
      
      if grandParentNode
        grandParentNode.readability[:contentScore] += contentScore/2
      end
    end
    
    topCandidate = nil
    candidates.each do |candidate|
      candidate.readability[:contentScore] = candidate.readability[:contentScore] * (1 - getLinkDensity(candidate))
      
      p "Candidate: " << candidate.name 
      if candidate['class']
        p " (" << candidate['class']
      end
      if candidate['id'] 
        p ":" << candidate['id']
      end
      p ") with score " 
      p candidate.readability[:contentScore]
      
      if (!topCandidate || candidate.readability[:contentScore] > topCandidate.readability[:contentScore]) 
        topCandidate = candidate
      end
    end
    
    articleContent = Nokogiri::XML::Node.new("div", @document)
    
    #xxx
    if topCandidate.blank?
      "nil"
    else
      if topCandidate.parent.blank?
        'nil'
      else
        siblingScoreThreshold = 10 > topCandidate.readability[:contentScore] * 0.2 ? 10 : topCandidate.readability[:contentScore] * 0.2
        siblingNodes = topCandidate.parent.children
    
        siblingNodes.each do |sibling|
      
          append = false
      
          next if !sibling
      
          append = true if sibling == topCandidate
      
          contentBonus = 0
          # Give a bonus if sibling nodes and top candidates have the example same classname */
          if sibling['class'] == topCandidate['class'] && topCandidate['class'] != ""
            contentBonus += topCandidate.readability[:contentScore] * 0.2
          end
      
          if sibling.readability && (sibling.readability[:contentScore] + contentBonus) >= siblingScoreThreshold
              append = true
          end
      
          if(sibling.name == "P") 
            linkDensity = getLinkDensity(sibling)
            nodeContent = sibling.text
            nodeLength  = nodeContent.length

            if(nodeLength > 80 && linkDensity < 0.25)
              append = true
            elsif (nodeLength < 80 && linkDensity == 0 && nodeContent =~ /\.( |$)/ )
              append = true
            end
          end
                      
          if append
          #  p articleContent.inner_html
            articleContent.add_child(sibling)
          end
      
        end
        articleContent
      end
    end
  end

  def getLinkDensity(node)
        links = node.css('a')
        textLength = node.content.length
        linkLength = 0;
        links.each do | link |
            linkLength += link.text.length;
        end      

        return linkLength / textLength;
  end


  def initializeNode (node) 
        node.readability = {:contentScore => 0}         

        case node.name 
            when 'DIV'
                node.readability[:contentScore] += 5
            when 'PRE'
            when 'TD'
            when 'BLOCKQUOTE'
                node.readability[:contentScore] += 3
            when 'ADDRESS'
            when 'OL'
            when 'UL'
            when 'DL'
            when 'DD'
            when 'DT'
            when 'LI'
            when 'FORM'
                node.readability[:contentScore] -= 3
            when 'H1'
            when 'H2'
            when 'H3'
            when 'H4'
            when 'H5'
            when 'H6'
            when 'TH'
                node.readability[:contentScore] -= 5
        end
       
        node.readability[:contentScore] += getClassWeight(node);
  end
  
  def getClassWeight (node) 
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

    return weight
  end
  
  def grabArticleTextOnly
    grabArticle.to_str.strip.gsub(/<div.*>|<p.*>|<table.*>|<tr.*>|\n|\t|\r/, '').squeeze(" ").gsub(/[^a-zA-z\s]/,'')
  end

  def getNextPageLink
    allLinks = @htmlDoc.css('a')
    baseURL = @url.scan(/^(http:\/\/[\w\d\-\.]+)(\/.*)$/).first.first
    
    p baseURL
    
    possible = {}
    allLinks.each do |link|
      
      href = link['href']
      
      next if link.text =~ @regexps[:extraneous] || link.text.length > 25 || href.match(baseURL) == nil || href.sub(baseURL, '').match(/\d/) == nil

      linkHrefLeftOver = href.sub(baseURL, '')
      
      if !possible.key? href 
        possible[href] = { :score => 0, :linkText => link.text, :href => href }
      else
        possible[href][:linkText] << link.text
      end
      
      ourLink = possible[href]
      linkData = link.text
      linkData << link['id'] if link['id']
      linkData << link['class'] if link['class']
      
      ourLink[:score] -= 25 if !href.include? baseURL 
            
      ourLink[:score] += 50 if linkData =~ @regexps[:nextLink]
      
      ourLink[:score] += 25 if linkData =~ /pag(e|ing|inat)/i
      
      ourLink[:score] -= 65 if linkData =~ /(first|last)/i && !link.text =~ @regexps[:nextLink]
      
      ourLink[:score] -= 50 if linkData =~ @regexps[:extraneous] || linkData =~ @regexps[:negative]
      
      ourLink[:score] -= 200 if linkData =~ @regexps[:prevLink]
      
      parent = link.parent
      positiveMatch = false
      negativeMatch = false
      
      while !parent.is_a? Nokogiri::HTML::Document do
        
        parentClassAndId = '' 
        parentClassAndId  << parent['class'] if !parent['class'].nil?
        parentClassAndId << parent['id'] if !parent['id'].nil?
        
        if !positiveMatch && parentClassAndId && parentClassAndId =~ /pag(e|ing|inat)/i
          positiveMatch = true
          ourLink[:score] += 25
        end
        if !negativeMatch && parentClassAndId && parentClassAndId =~ @regexps[:negative]
          if !parentClassAndId =~ @regexps[:positive]
            ourLink[:score] -= 25
            negativeMatch = true 
          end
        end
        
        parent = parent.parent
        
      end
      
      ourLink[:score] += 25 if href =~ /p(a|g|ag)?(e|ing|ination)?(=|\/)[0-9]{1,2}/i || href =~ /(page|paging)/i
      
      ourLink[:score] -= 15 if href =~ @regexps[:extraneous]
      
      if link.text.to_i
        if link.text.to_i == 1
          ourLink[:score] -= 15 
        else
          ourLink[:score] += [0, 10 - link.text.to_i].max
        end
      end
      
      p possible[href][:href]
      p possible[href][:score]
      
      p possible.values
      
    end
  end
  
  def grabEntireArticle
    grabArticleTextOnly
    
    #while getNextPageLink
    
  end

end
