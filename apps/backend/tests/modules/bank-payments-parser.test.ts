import { describe, expect, it } from 'vitest'
import { parseBankPayment } from '@ptas/bank-parsers'

describe('bank payment parser', () => {
  it('parses the original ABA USD payment sentence', () => {
    const parsed = parseBankPayment(
      '0.10 USD is paid by KHQR Lay Bunnavitou(*616) on Sep 30, 2024 13:43:49 at DingDing by B.LAY with Transaction ID: 172767862874229, APV: 310982',
    )

    expect(parsed).toMatchObject({
      bank: 'ABA',
      amount: '0.10',
      currency: 'USD',
      senderName: 'Lay Bunnavitou',
      senderAccount: '616',
      transactionId: '172767862874229',
      apv: '310982',
    })
    expect(parsed?.paidAt).toBeInstanceOf(Date)
  })

  it('parses KHR payments with thousand separators', () => {
    const parsed = parseBankPayment(
      '4,000 KHR is paid by KHQR Sok Dara(*123) on May 15, 2026 09:10:11 at Ptas168 with Transaction ID: 987654321, APV: 102030',
    )

    expect(parsed).toMatchObject({
      amount: '4000',
      currency: 'KHR',
      senderName: 'Sok Dara',
      senderAccount: '123',
      transactionId: '987654321',
      apv: '102030',
    })
  })

  it('parses copied field-style payment text with KHR before the amount', () => {
    const parsed = parseBankPayment([
      'ACLEDA notification',
      'Amount: KHR 4,000',
      'Sender: Sok Dara',
      'Account: *123',
      'Transaction ID: TXN-42',
      'Date: 15/05/2026 09:10:11',
    ].join('\n'))

    expect(parsed).toMatchObject({
      bank: 'ACLEDA',
      amount: '4000',
      currency: 'KHR',
      senderName: 'Sok Dara',
      senderAccount: '123',
      transactionId: 'TXN-42',
    })
    expect(parsed?.paidAt.getFullYear()).toBe(2026)
    expect(parsed?.paidAt.getMonth()).toBe(4)
    expect(parsed?.paidAt.getDate()).toBe(15)
  })

  it('ignores messages without a supported USD or KHR currency', () => {
    const parsed = parseBankPayment(
      '10 THB is paid by KHQR Someone(*999) on May 15, 2026 09:10:11 with Transaction ID: 111',
    )

    expect(parsed).toBeNull()
  })
})
