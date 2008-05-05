require 'rubygems'
require 'open-uri'
require 'hpricot'
require 'uri'

class Organisation < ActiveRecord::Base

  has_many :submissions, :as => :submitter

  validates_presence_of :name
  # validates_presence_of :url
  validates_presence_of :slug

  validates_uniqueness_of :name
  validates_uniqueness_of :url, :allow_nil => true
  validates_uniqueness_of :slug

  before_validation_on_create :normalize_site_url,
    :normalize_name,
    :create_slug_from_name,
    :grab_thumbnail,
    :default_alternative_names_to_blank

  validates_format_of :url, :with => /^((?:[-a-z0-9_]+\.)+[a-z]{2,})$/, :allow_nil => true

  before_save :populate_count_of_mentions
  after_save :expire_cached_pages

  def self.education_domains
    %w[ac.nz school.nz]
  end

  def self.commerical_domains
    %w[co.nz com com.au]
  end

  def self.government_domains
    %w[govt.nz www.nelsoncitycouncil.co.nz www.franklindistrict.co.nz]
  end

  def self.other_domains
    %w[org.nz net.nz org info asn.au www.ncwnz.co.nz]
  end

  def self.from_name text
    name = text[/(^.+)\s(Supp\s?\d+|Appendix(\s?\d+)?|Part\s?\d+)$/i, 1] || text
    organisation = Organisation.find_by_name(name)
    unless organisation
      second_try = name[/(^.+)\s(Limited|Inc)$/i, 1] ||
          (name[/Incorporated/] ? name.sub('Incorporated', 'Inc') :
            (name[/^The /] ? name.sub(/^The /, '') :
              (name[/New Zealand/] ? name.sub('New Zealand', 'NZ') :
                (name[/NZ/] ? name.sub('NZ','New Zealand') : "#{name.strip} Limited")
              )
            )
          )

      organisation = Organisation.find_by_name(second_try) if second_try != name

      unless organisation
        if name[/^The /]
          third_try = "#{name.sub(/^The /, '')} of New Zealand"
          organisation = Organisation.find_by_name(third_try)
        end
      end
    end
    organisation
  end

  def category
    domain = url_domain
    if Organisation.other_domains.include?(domain) || Organisation.other_domains.include?(url)
      'Other'
    elsif Organisation.government_domains.include?(domain) || Organisation.government_domains.include?(url)
      'Government'
    elsif Organisation.education_domains.include?(domain)
      'Education'
    elsif Organisation.commerical_domains.include?(domain)
      'Commercial'
    else
      'Other'
    end
  end

  def url_domain
    if url
      parts = url.split('.')
      if parts.last.size == 2
        "#{parts[parts.size - 2]}.#{parts.last}"
      else
        parts.last
      end
    else
      nil
    end
  end

  def submitted_on_items
    submissions.group_by(&:business_item).keys
  end

  def submitted_on_count
    submitted_on_items.size
  end

  def thumbnail
    RAILS_ROOT+'/public'+thumbnail_path
  end

  def thumbnail_path
    '/images/orgs/'+url+'.gif'
  end

  def id_hash
    { :name => slug }
  end

  def populate_wikipedia_url
    unless wikipedia_url
      encoded_name = URI.encode name
      url = "http://www.google.com/search?&q=%22#{encoded_name}%22%20site%3Aen.wikipedia.org"
      results = (Hpricot(open(url)) / 'h2.r/a')
      if results.size > 0
        self.wikipedia_url = results.first.attributes['href']
      else
        url = "http://www.google.com/search?&q=#{encoded_name}%20site%3Aen.wikipedia.org"
        results = (Hpricot(open(url)) / 'h2.r/a')
        if results.size > 0
          self.wikipedia_url = results.first.attributes['href']
        end
      end
    end
  end

  def populate_count_of_mentions
    self.count_of_mentions = live_count_of_debates_mentioned_in
  end

  def live_count_of_debates_mentioned_in
    find_mentions.inject(0) {|sum,group| sum + group.size}
  end

  def search_names
    if alternate_names.blank?
      [name]
    else
      alternate_names.split('|')
    end
  end

  def find_mentions
    Contribution.find_mentions search_names
  end

  def response host, path
    resp = nil
    Net::HTTP.start(host) do |http|
      resp = http.get(path,
          {
            "Host" => host,
            "User-Agent" => "Mozilla/5.0 (Windows; U; Windows NT 5.1; rv:1.7.3) Gecko/20040913 Firefox/0.10.1",
            "Accept" => "text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,image/png,*/*;q=0.5",
            "Accept-Language" => 'en-us,en;q=0.7,en-gb;q=0.3',
            "Accept-Encoding" => 'gzip,deflate',
            "Accept-Charset" => 'ISO-8859-1,utf-8;q=0.7,*;q=0.7'
      })
    end
    resp
  end

  def grab_thumbnail
    if (RAILS_ENV != 'test' and url and !File.exist?(thumbnail))
      uri = url.sub('www.','')
      resp = response "www.alexa.com", "/data/details/main/#{uri}"

      doc = Hpricot resp.body
      alt = "Thumbnail image of #{uri}"
      img = doc.at(%Q|img[@alt="#{alt}"]|)
      if img
        img_src = img.attributes['src'].to_s
        resp = response "ast.amazonaws.com", img_src.sub("http://ast.amazonaws.com",'')
        location = resp.header['location']

        unless location == 'http://client.alexa.com/common/images/noimagel.gif'
          if (match = %r|^http://([^/]+)(.*)$|.match location)
            resp = response match[1], match[2]
            if resp.code == "200"
              File.open(thumbnail, 'w') do |f|
                f.write resp.body
              end
            end
          end
        end
      end
    end
  end
  protected

    def uncache path
      if File.exist?(path)
        puts 'deleting: ' + path.sub(Debate::CACHE_ROOT, '')
        File.delete(path)
      end
    end

    def expire_cached_pages
      return unless ActionController::Base.perform_caching

      organisation_path = "#{Debate::CACHE_ROOT}/organisations/#{slug}"

      uncache "#{organisation_path}/mentions.cache"
      uncache "#{organisation_path}.cache"
      uncache "#{Debate::CACHE_ROOT}/organisations.cache"
    end

    def default_alternative_names_to_blank
      unless alternate_names
        self.alternate_names = ''
      end
    end

    def normalize_site_url
      if url
        self.url.chomp!('/')
        self.url.sub!('http://','')
      end
    end

    def normalize_name
      if name
        if (match = /(^.+) Supp\d+$/.match name)
          self.name = match[1]
        end
      end
    end

    def create_slug_from_name
      if name
        slug = name.to_latin.to_s.downcase.strip.
            gsub(' ','_').gsub("'",'').gsub('"','').
            gsub('(','').gsub(')','').gsub('.','').
            gsub(',','').gsub('&','and')
        slug.sub!('the_','') if slug.starts_with?('the_')
        slug.chomp!('_inc')

        slug.sub!('new_zealand','nz') if slug.include?('new_zealand')

        if Organisation.find_by_slug(slug)
          index = 2
          temp_slug = slug + '_' + index.to_s
          while Organisation.find_by_slug(temp_slug)
            index = index.next
            temp_slug = slug + '_' + index.to_s
          end
          slug = temp_slug
        end
        self.slug = slug
      end
    end

end
