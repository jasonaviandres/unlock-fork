import { useRouter } from 'next/router'
import { useEffect, useState } from 'react'
import { PaywallConfig } from '~/unlockTypes'
import { CheckoutForm } from './elements/CheckoutForm'
import { CheckoutPreview } from './elements/CheckoutPreview'

const Header = () => {
  return (
    <header className="flex flex-col gap-4">
      <h1 className="text-4xl font-bold text-white">Checkout Builder</h1>
      <span className="text-base text-gray-200">
        Customize your membership checkout experience. The preview on the left
        is updated in realtime.
      </span>
    </header>
  )
}

export const CheckoutUrlPage = () => {
  const { query } = useRouter()

  const { lock: lockAddress, network } = query ?? {}

  // TODO @kalidou : let's use the default values from zod?
  const [paywallConfig, setPaywallConfig] = useState<PaywallConfig>({
    locks: {},
    pessimistic: true,
    skipRecipient: true,
  })

  const onAddLocks = (locks: any) => {
    setPaywallConfig({
      ...paywallConfig,
      locks,
    })
  }

  const onBasicConfigChange = (fields: Partial<PaywallConfig>) => {
    const hasDefaultLock =
      Object.keys(fields?.locks ?? {}).length === 0 && lockAddress && network

    if (hasDefaultLock) {
      fields = {
        ...fields,
        locks: {
          [lockAddress as string]: {
            network: parseInt(`${network!}`),
          },
        },
      }
    }

    setPaywallConfig({
      ...paywallConfig,
      ...fields,
    })
  }

  const addDefaultLockFromQuery = () => {
    if (!lockAddress && !network) return null
    onAddLocks({
      [lockAddress as string]: {
        network: parseInt(`${network!}`),
        skipRecipient: true,
      },
    })
  }

  useEffect(() => {
    addDefaultLockFromQuery()
  }, [])

  return (
    <div className="flex flex-col w-full min-h-screen gap-8 pt-10 pb-20 md:flex-row">
      <div className="md:w-1/2">
        <CheckoutPreview paywallConfig={paywallConfig} />
      </div>
      <div className="flex flex-col gap-4 md:w-1/2">
        <Header />
        <CheckoutForm
          onAddLocks={onAddLocks}
          onBasicConfigChange={onBasicConfigChange}
          paywallConfig={paywallConfig}
        />
      </div>
    </div>
  )
}
