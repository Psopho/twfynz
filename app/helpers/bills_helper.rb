module BillsHelper

  def bill_event_description bill_event
    # "#{bill_event.bill.bill_name}-#{bill_event.name}"
    url = bill_event_url(bill_event)
    date = format_date(bill_event.date)
    event_name = bill_event.name
    case bill_event.source.class.name
      when 'SubDebate'
        bill_event_debate_description event_name, url, date, bill_event.source
      when 'NzlEvent'
        bill_event_nzl_event_description event_name, url, bill_event.source
      else
        bill_event_notification_description bill_event.bill.bill_name, event_name, date, url
    end
  end

  def bill_event_notification_description bill_name, event_name, date, url
    case event_name.downcase.sub(' ','_').to_sym
      when :introduction
        "<p>The #{link_to bill_name, url} was introduced to parliament on #{date}.</p>"
      when :submissions_due
        "<p>Public submissions are now being invited on the #{link_to bill_name, url}.</p><p>Submissions are due by #{date}.</p>"
      when :first_reading, :second_reading, :third_reading
        "<p>The #{link_to bill_name, url} had a #{event_name.downcase} debate on #{date}.</p><p>More details will be available after Parliament publishes the debate transcript.</p>"
      when :sc_reports
        "<p>The select committee report on the #{link_to bill_name, url} is due on #{date}.</p>"
      when :in_committee
        "<p>The select committee report on the #{link_to bill_name, url} is due on #{date}.</p>"
      else
        "#{link_to(event_name, url)} on #{date}."
    end
  end

  def bill_event_debate_description event_name, url, date, debate
    link_text = "#{event_name.downcase} debate on #{date}"
    "The bill's #{link_to(link_text, url)} has been published."
  end

  def bill_event_nzl_event_description event_name, url, nzl_event
    "The bill as #{link_to(event_name.sub('introduction','introduced'), url)} published at legislation.govt.nz."
  end

  def submission_alert bill
    if (bill.respond_to? :submission_dates and (bill.submission_dates.size > 0))
      submission_date = bill.submission_dates[0]
      if Date.today <= submission_date.date
        url = "http://www.parliament.nz/en-NZ/SC/SubmCalled#{submission_date.parliament_url}"
        details = submission_date.details.chomp('.')
        %Q[#{link_to(details, url)} (link to external Parliament website).]
      else
        ''
      end
    else
      ''
    end
  end

  def split_bill_details bill_event
    details = ''
    bill = bill_event.bill
    if bill.nzl_events
      events = bill.nzl_events.select {|e| e.version_stage == 'reported' || e.version_stage == 'wip version updated' }.sort_by(&:publication_date)
      if events.size > 0
        details = %Q[#{link_to('View the bill', events.last.link)} as reported from the #{events.last.version_committee} at the New Zealand Legislation website.]
      end
    end
    details
  end

  def committee_report_details bill_event
    details = ''
    bill = bill_event.bill
    if bill.was_reported_by_committee?
      details = %Q[The #{link_to_committee(bill.referred_to_committee)} reported on this bill.]
    end
    if bill.nzl_events
      events = bill.nzl_events.select {|e| e.version_stage == 'reported' || e.version_stage == 'wip version updated' }.sort_by(&:publication_date)
      if events.size > 0
        details += %Q[ #{link_to('View the bill', events.last.link)} as reported from the #{events.last.version_committee} at the New Zealand Legislation website.]
      end
    end
    details
  end

  def committee_details bill_event
    bill = bill_event.bill
    if bill.is_before_committee?
      %Q[The #{link_to_committee(bill.referred_to_committee)} is considering this bill.]
    end
  end

  def mp_in_charge bill
    %Q[#{link_to_mp(bill.member_in_charge)} #{is_was(bill)} the member in charge of this #{bill_type(bill).camelize}.]
  end

  def is_was bill
    bill.current? ? 'is' : 'was'
  end

  def debate_date date, debates
    if debates.nil?
      format_date date
    elsif debates.size == 1
      format_date debates.first.date
    else
      debate_dates debates
    end
  end

  def debate_dates debates
    debates.reverse.collect do |d|
      date = format_date(d.date)
      date += ' (resumed)' if (d.contributions.size > 0 and d.contributions.first.text.include? 'Debate resumed')
      link_to(date, get_url(d))
    end.join(',<br />')
  end

  def vote_question vote
    vote ? vote.question : ''
  end

  def vote_ayes bill_event
    if bill_event.has_votes?
      bill_event.votes.collect { |v| (v and v.ayes_count != 0) ? v.ayes_count : '-' }.join('<br /><br />')
    else
      ''
    end
  end

  def vote_noes bill_event
    if bill_event.has_votes?
      bill_event.votes.collect { |v| (v and v.noes_count != 0) ? v.noes_count : '-' }.join('<br /><br />')
    else
      ''
    end
  end

  def vote_abstentions bill_event
    if bill_event.has_votes?
      bill_event.votes.collect { |v| (v and v.abstentions_count != 0) ? v.abstentions_count : '-' }.join('<br /><br />')
    else
      ''
    end
  end

  def result_from_vote bill_event
    votes = bill_event.votes
    result = votes.compact.collect(&:result).join('<br /><br />')

    if votes.size == 1
      debate = bill_event.debates.first
      contributions = debate.contributions
      last = contributions.last
      if last.is_procedural?
        if last.text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'') == 'Motion agreed to.'
          result += '<br /><br />' + last.text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'').chomp('.') + ':<br />'
          if (contributions.size > 1 and contributions[contributions.size-2].is_speech?)
            if match = contributions[contributions.size-2].text.match(/That the .*/)
              result += match[0].gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'')
            end
          end
        else
          result += '<br /><br />' + last.text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'')
        end
      elsif (contributions.size > 1 and contributions[contributions.size-2].is_procedural?)
        result += '<br /><br />' + contributions[contributions.size-2].text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'')
      end
    end

    result = make_committee_a_link result, bill_event.bill, votes
    result
  end

  def result_from_contributions bill_event
    debate = bill_event.debates.first
    bill = bill_event.bill
    if debate.contributions.size == 0
      ''
    else
      contributions = debate.contributions.reverse
      i = 0
      statement = contributions[i]
      results = []

      if statement.text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'') == 'Motion agreed to.'
        result = statement.text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'').chomp('.') + ':<br />'

        if (contributions.size > 1 and contributions[1].is_speech?)
          if match = contributions[1].text.match(/That the .*/)
            result += match[0].gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'').gsub('</i>','')
          end
        end

        if (contributions.size > 2 and contributions[2].is_procedural?)
          if contributions[2].text.include? 'Bill read'
            result = contributions[2].text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'') + '<br /><br />' + result
          end
        end

        result.sub!(':<br />','.') if result.ends_with?(':<br />')
      else
        while (statement and statement.is_procedural?)
          results << statement.text.gsub(/<[pi]>/, '').gsub(/<\/[pi]>/,'') unless statement.text[/(Waiata|Sitting suspended)/]
          i = i.next
          statement = (i != contributions.size) ? contributions[i] : nil
          statement = nil if (statement and statement.text.include? 'House resumed')
          statement = nil if (statement and statement.text.gsub('<p>', '').strip[/^(Clause|\[An interpretation)/])
        end
        result = results.reverse.flatten.join('<br /><br />')
      end
      result = make_committee_a_link result, bill
      result
    end
  end

  def introduction bill_event
    bill = bill_event.bill
    intro = mp_in_charge(bill)
    if bill.nzl_events
      events = bill.nzl_events.select {|e| e.version_stage == 'introduction'}.sort_by(&:publication_date)
      if events.size > 0
        intro += %Q[<br/><br/>#{link_to('View the bill', events.last.link)} at introduction at the NZ Legislation website.]
      end
    end
  end

  def bill_event_url bill_event
    unless bill_event.source
      bill = bill_event.bill
      show_bill_url(bill, :bill_url => bill.url).sub(/\d+\?bill_url=/,'')
    else
      case bill_event.source
        when NzlEvent
          bill_event.source.link
        when Debate, SubDebate
          get_url(bill_event.source)
        else
          bill_event.source.class.name
      end
    end
  end

  def bill_event_name bill_event
    debate_name bill_event.name, bill_event.debates
  end

  def bill_event_dates bill_event
    debate_date bill_event.date, bill_event.debates
  end

  def bill_event_result_summary bill_event
    if !bill_event.has_debates?
      case bill_event.name
        when 'Introduction'
          introduction bill_event
        when 'Submissions Due'
          committee_details bill_event
        when 'SC Reports'
          committee_report_details bill_event
        when 'Third Reading'
          bill_event.was_split_at_third_reading? ? split_bill_details(bill_event) : ''
        when 'Committee of the whole House: Order of the day for committal discharged'
          'Order of the day for committal discharged.'
        when 'Consideration of report: Order of the day for consideration of report discharged'
          'Order of the day for consideration of report discharged.'
        when 'Second reading: Order of the day for second reading discharged'
          'Order of the day for second reading discharged.'
        when 'First reading: Order of the day for first reading discharged'
          'Order of the day for first reading discharged.'
        else
          ''
      end
    elsif bill_event.has_votes?
      view_bill = bill_event.was_split_at_third_reading? ? split_bill_details(bill_event) : ''
      result = result_from_vote(bill_event)
      result += "<br/><br/>#{view_bill}" unless view_bill.blank?
      result
    else
      result_from_contributions bill_event
    end
  end

  def vote_result vote
    vote ? vote.result : ''
  end

  def bill_type_label bill
    type = bill_type(bill).chomp(' bill')
    type = 'Govt.' if type == 'Government'
    type = 'Member' if type == "Member's"
    type
  end

  def party_name bill
    party = bill.party_in_charge ? bill.party_in_charge.short : 'no party '+ bill.member_in_charge.full_name
    party = 'Progres-<br/>sive' if party == 'Progressive'
    party
  end

  private

    def make_committee_a_link result, bill, votes=nil
      if bill
        committee = bill.referred_to_committee
        if (committee and result.include?(committee.full_committee_name))
          name = committee.full_committee_name
          result.sub!(name, link_to(name, show_committee_url(:committee_url => committee.url) ) )
        elsif (match = (/the (.* Committee)/.match result))
          name = match[1]
          committee = Committee::from_name name
          if committee
            if votes
              votes.each do |vote|
                if (vote.votes_count > 0 and (vote.ayes_count > vote.noes_count))
                  bill.referred_to_committee = committee
                  bill.save
                end
              end
            end
            result.sub!(name, link_to(name, show_committee_url(:committee_url => committee.url) ) )
          end
        end
      end
      result
    end
end
