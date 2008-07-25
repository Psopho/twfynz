class Bill < ActiveRecord::Base

  belongs_to :member_in_charge, :class_name => 'Mp', :foreign_key => 'member_in_charge_id'
  belongs_to :referred_to_committee, :class_name => 'Committee',:foreign_key => 'referred_to_committee_id'

  belongs_to :formerly_part_of, :class_name => 'Bill', :foreign_key => 'formerly_part_of_id'
  has_many :divided_into_bills, :class_name => "Bill", :foreign_key => 'formerly_part_of_id'
  has_many :debate_topics, :as => :topic
  has_many :sub_debates, :as => :about
  has_many :submissions, :as => :business_item
  has_many :submission_dates
  has_many :nzl_events, :as => :about

  validates_presence_of :bill_name
  validates_presence_of :url
  validates_presence_of :earliest_date
  validates_presence_of :member_in_charge_id

  validates_presence_of :parliament_url

  before_validation :populate_former_name,
      :populate_formerly_part_of,
      :reset_earliest_date,
      :populate_committee

  before_validation_on_create :populate_member_in_charge,
      :default_negatived,
      :create_url_identifier,
      :populate_plain_bill_name,
      :populate_plain_former_name

  after_save :expire_cached_pages

  class << self

    def bills_from_text_and_date text, date
      bill_text = text.gsub(/(\d)\), Te/, '\1), the Te')
      bill_text = bill_text.gsub(/Bill( \([^\)]+\))? and the/,'Bill\1, and the')
      bills = bill_text.split(/,( and)? the/).collect do |name|
        name = name.match(/[a-z ]*(.*)/)[1]
        name = name.chomp(', ').strip unless name.empty?
        name.empty? ? nil : Bill.from_name_and_date(name, date)
      end.compact
    end

    def from_name_and_date name, date
      from_name_and_date_by_method name, date, :find_all_by_bill_name
    end

    def find_all_by_plain_bill_name_and_year name, year
      bills = find_all_by_plain_bill_name name
      bills = find_all_by_plain_former_name name if bills.empty?
      selected = select_by_year bills, year
      selected = select_by_year bills, (year-1) if selected.empty?
      selected = select_by_year bills, (year-2) if selected.empty?
      selected
    end

    def select_by_year bills, year
      selected = bills.select do |b|
        introduced_that_year = b.introduction && b.introduction.year == year
        if introduced_that_year
          true
        elsif (formerly = b.formerly_part_of)
          formerly.introduction && formerly.introduction.year == year
        else
          false
        end
      end
    end

    def from_name_and_date_by_method name, date, method
      bills = send(method, name)
      bills = send(method, name.gsub('-',' - ')) if bills.empty?
      bills = send(method, name.gsub('’',"'")) if bills.empty?
      bills = send(method, name.gsub('’',"'").chomp(')')) if bills.empty?
      bills = send(method, name.gsub('’',"'").chomp(')').sub(')',') ').sub('(',' (').squeeze(' ')) if bills.empty?
      bills = send(method, name.gsub('’',"'").chomp(')').sub(')',') ').sub('(',' (').squeeze(' ').sub('Appropriations','Appropriation')) if bills.empty?
      bills = send(method, name.gsub('’',"'").chomp(')').sub(')',') ').sub('(',' (').squeeze(' ').sub('RateAmendments','Rate Amendments')) if bills.empty?
      bills = send(method, name.gsub('’',"'").chomp(')').sub(')',') ').sub('(',' (').squeeze(' ').sub('andAsure','and Asure')) if bills.empty?
      bills = bills.select {|b| b.royal_assent.nil? || (b.royal_assent > date) }
      bills = bills.select {|b| b.introduction.nil? || (b.introduction <= date) }

      if bills.size == 1
        bills[0]
      elsif bills.empty?
        if method == :find_all_by_bill_name
          from_name_and_date_by_method name, date, :find_all_by_former_name
        else
          raise "no bills match: #{name}, #{date.to_s}"
        end
      else
        begin
          the_date = date
          if the_date.is_a? String
            the_date = Date.parse(date)
          end
          days_back = bills.collect {|b| [(the_date - b.introduction).to_i, b] }
          bill = days_back.sort.first[1]
          bill
        rescue Exception => e
          raise "#{bills.size} bills match: #{name}, #{date.to_s}"
        end
      end
    end

    def find_all_current
      sql = 'select * from bills where royal_assent is null and first_reading_negatived = 0 and second_reading_negatived = 0 and withdrawn is null and second_reading_withdrawn is null and committal_discharged is null and consideration_of_report_discharged is null and second_reading_discharged is null and first_reading_discharged is null'
      sql += %Q[ and type = "#{self.to_s}"] unless self == Bill
      bills = find_by_sql(sql)
      bills.select { |b| b.current? && b.url != 'business_law_reform' }
    end

    def find_all_negatived
      find_all_with_debates.select(&:negatived?)
    end

    def find_all_assented
      find_all_with_debates.select(&:assented?)
    end

    def sort_events_by_date events
      events = events.sort do |a,b|
        date = a[0]
        other_date = b[0]
        comparison = date <=> other_date
        if comparison == 0
          name = a[1]
          other_name = b[1]
          if (name.include? 'First' and (other_name.include? 'Second' or other_name.include? 'Third'))
            comparison = -1
          elsif (name.include? 'Second' and (other_name.include? 'Third'))
            comparison = -1
          elsif (name.include? 'Second' and (other_name.include? 'First'))
            comparison = +1
          elsif (name.include? 'Third' and (other_name.include? 'First' or other_name.include? 'Second'))
            comparison = +1
          else
            comparison = 0
          end
        end
        comparison
      end
      events
    end
  end

  def probably_not_divided?
    year = Date.today.year
    divided_into_bills.empty? or (divided_into_bills.size > 0 and (last_event and last_event[0].year == year))
  end

  def current?
    if divided_into_bills.empty?
      ( (not(negatived? or assented? or withdrawn? or discharged?)) and probably_not_divided? )
    else
      divided_into_bills.inject(false) {|current, bill| current && bill.current?}
    end
  end

  def full_name
    bill_name
  end

  def negatived?
    first_reading_negatived or second_reading_negatived
  end

  def assented?
    royal_assent ? true : false
  end

  def is_before_committee?
    referred_to_committee and referred_to_committee.bills_before_committee.include?(self)
  end

  def was_reported_by_committee?
    referred_to_committee and referred_to_committee.reported_bills.include?(self)
  end

  def last_event
    events_by_date.last
  end

  def last_event_date
    last_event ? last_event[0] : nil
  end

  def last_event_name
    last_event ? last_event[1] : nil
  end

  def party_in_charge
    member_in_charge ? member_in_charge.party : nil
  end

  def last_event_debates
    debates_by_name, names = Debate::get_debates_by_name debates
    name = last_event[1]
    debates_by_name ? debates_by_name[name] : nil
  end

  def debates
    if debate_topics.size > 0
      sub_debates + debate_topics.collect { |t| t.debate }
    else
      sub_debates
    end
  end

  def debate_count
    [count_by_about('U'), count_by_about('A'), count_by_about('F')].max
  end

  def votes_by_name
    debates = self.debates
    if debates.size == 0
      debates_by_name, names, votes_by_name = nil,nil,nil
    else
      debates_by_name, names = Debate::get_debates_by_name debates
      votes_by_name = get_votes_by_name names, debates_by_name
    end
    return debates_by_name, names, votes_by_name
  end

  def events_by_date_debates_by_name_names_votes_by_name
    debates_by_name, names, votes_by_name = self.votes_by_name
    events_by_date = self.events_by_date

    if debates_by_name
      missed = debates_by_name.keys - events_by_date.collect {|e| e[1]}
      if missed.size > 0
        missed.each do |name|
          events_by_date << [debates_by_name[name].last.date, name]
        end
        events_by_date = Bill::sort_events_by_date events_by_date
      end
    end
    return events_by_date, debates_by_name, names, votes_by_name
  end

  def events_by_date
    events = {}
    events[introduction] = 'Introduction' if introduction
    events[first_reading] = 'First Reading' if first_reading
    events[sc_reports] = 'SC Reports' if sc_reports
    events[submissions_due] = 'Submissions Due' if submissions_due
    events[second_reading] = 'Second Reading' if second_reading
    events[committee_of_the_whole_house] = 'In Committee' if committee_of_the_whole_house
    events[third_reading] = 'Third Reading' if third_reading
    events[royal_assent] = 'Royal Assent' if royal_assent

    events[withdrawn] = 'Withdrawn' if withdrawn
    events[second_reading_withdrawn] = 'Second reading withdrawn' if second_reading_withdrawn
    events[committal_discharged] = 'Committee of the whole House: Order of the day for committal discharged' if committal_discharged
    events[consideration_of_report_discharged] = 'Consideration of report: Order of the day for consideration of report discharged' if consideration_of_report_discharged
    events[second_reading_discharged] = 'Second reading: Order of the day for second reading discharged' if second_reading_discharged
    events[first_reading_discharged] = 'First reading: Order of the day for first reading discharged' if first_reading_discharged

    Bill.sort_events_by_date events
  end

  def populate_plain_bill_name
    self.plain_bill_name = strip_name(bill_name) if bill_name
  end

  def populate_plain_former_name
    self.plain_former_name = strip_name(former_name) if former_name
  end

  def strip_name name
    name.tr("-:/,'",'').gsub('(','').gsub(')','')
  end

  def expire_cached_pages
    return unless ActionController::Base.perform_caching

    uncache "#{Debate::CACHE_ROOT}/bills/#{url}.cache"

    if referred_to_committee
      uncache "#{Debate::CACHE_ROOT}/committees/#{referred_to_committee.url}.cache"
    end

    if member_in_charge
      uncache "#{Debate::CACHE_ROOT}/mps/#{member_in_charge.id_name}.cache"
    end
    uncache "#{Debate::CACHE_ROOT}/bills.cache"
  end

  protected

    def uncache path
      if File.exist?(path)
        puts 'deleting: ' + path.sub(Debate::CACHE_ROOT, '')
        File.delete(path)
      end
    end

    def self.find_all_with_debates
      bills = find(:all, :include => [:sub_debates, {:debate_topics => :debate}])
      bills.select { |b| b.debate_count > 0 or b.debate_topics.size >  0 }
    end

    def count_by_about publication_status
      debate_count = sub_debates.select {|d| d.publication_status == publication_status }.size
      debate_count + debate_topics.select {|t| t.debate.publication_status == publication_status }.size
    end

    def get_votes_by_name names, debates_by_name
      names.inject({}) do |by_name, name|
        debate = debates_by_name[name].first
        votes = debate.votes.select { |v| v and v.question.include?('be now read') }
        if votes.empty?
          votes = debate.votes.select { |v| v and v.result.include?('Bill referred') }
        else
          contributions = debate.contributions
          if (contributions.last and contributions.last.is_vote?)
            vote = contributions.last.vote
            if (vote != votes[0])
              votes << vote
            end
          end
        end

        if (votes.empty?)
          contributions = debate.contributions
          if (contributions.last)
            last = contributions.last
            if (last.is_vote?)
              votes = [last.vote]
            elsif ((last.text.include? 'Bill to be reported without amendment presently.' or
              last.text.include? 'Bill referred to') and
              contributions[contributions.size-2].is_vote?)
              votes = [contributions[contributions.size-2].vote]
            end
          end
        end
        by_name[name] = votes.empty? ? nil : votes
        by_name
      end
    end

    def withdrawn?
      (withdrawn or second_reading_withdrawn) ? true : false
    end

    def committal_discharged?
      committal_discharged ? true : false
    end

    def consideration_of_report_discharged?
      consideration_of_report_discharged ? true : false
    end

    def second_reading_discharged?
      second_reading_discharged ? true : false
    end

    def first_reading_discharged?
      first_reading_discharged ? true : false
    end

    def discharged?
      committal_discharged? or consideration_of_report_discharged? or second_reading_discharged? or first_reading_discharged?
    end

    def referred_to= name
      @referred_to = name
    end

    def referred_to
      @referred_to
    end

    def mp_name= name
      @mp_name = name
    end

    def mp_name
      @mp_name
    end

    def bill_change= change
      @bill_change = change
    end

    def bill_change
      @bill_change
    end

    def populate_former_name
      if bill_change and not(bill_change.include? 'Formerly part of') and (bill_change.include? 'Formerly ')
        self.former_name = bill_change.gsub('(Formerly ','').chomp(')')
      end
    end

    def populate_formerly_part_of
      if formerly_part_of.blank?
        if bill_change and bill_change.include? 'Formerly part of'
          former = bill_change.gsub('(Formerly part of ', '').chomp(')')
          if former_bill = Bill.find_by_bill_name(former)
            self.formerly_part_of_id = former_bill.id
          else
            raise 'Validation failed: cannot find former bill from bill_change: ' + bill_change
          end
        end
      end
    end

    def populate_committee
      if referred_to_committee_id.blank?
        if referred_to
          name = referred_to.gsub(/M.*ori /, 'Maori ')
          if (committee = Committee.from_name name)
            self.referred_to_committee_id = committee.id
          else
            raise 'Validation failed: cannot find committee from referred_to: ' + referred_to
          end
        end
      end
    end

    def populate_member_in_charge
      if member_in_charge_id.blank?
        if mp_name
          mp = Mp::from_name(mp_name)
          if mp
            self.member_in_charge_id = mp.id
          else
            raise 'Validation failed: cannot find member in charge from mp_name: ' + mp_name
          end
        else
          raise 'Validation failed: :mp_name can\'t be blank'
        end
      end
    end

    def reset_earliest_date
      self.introduction = '2008-07-02' if bill_name == 'Privacy (Cross-border Information) Amendment Bill'

      dates = [introduction, first_reading, second_reading,
          committee_of_the_whole_house, third_reading, royal_assent].compact.sort
      if dates.size > 0
        self.earliest_date = dates.first
      elsif formerly_part_of_id != nil
        parent_bill = Bill.find(formerly_part_of_id)
        if (date = parent_bill.earliest_date)
          self.earliest_date = date
        end
      end
    end

    def default_negatived
      self.first_reading_negatived = 0 unless self.first_reading_negatived
      self.second_reading_negatived = 0 unless self.second_reading_negatived
    end

    def create_url_identifier
      if bill_name and not url
        url = bill_name.to_latin.to_s.downcase.
            tr(',:','').gsub('(','').gsub(')','').
            gsub('/ ',' ').tr('/',' ').
            gsub(/ng\S*ti/, 'ngati').
            tr("'",'').gsub(' and', '').
            gsub('new zealand', 'nz').
            gsub(' bill', '').
            gsub(' miscellaneous', '').
            gsub(' provisions', '').
            gsub(' as a','').gsub(' - ','-').
            gsub('  ',' ').tr(' ','_')

        num = /.*(_no_.*)/.match url

        if url.size > 40
          cut_off = url[40..40]
          in_word = /[A-Za-z0-9]/.match cut_off

          url = url[0..39]

          if in_word
            url = url[0..(url.rindex('_')-1)]
          end
        end

        if num and not url.include? num[1]
          if url.size < 35
            url = url + num[1]
          else
            url = url[0..34].chomp('_')+num[1]
          end
        end
        bill = Bill.find_by_url(url)

        if bill
          self.url = "#{url}_#{earliest_date.year.to_s}"
        else
          self.url = url
        end
      end
    end

end
